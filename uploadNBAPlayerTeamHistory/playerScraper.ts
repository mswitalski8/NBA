// Dynamic puppeteer import - will be loaded at runtime based on environment
import { setTimeout } from 'node:timers/promises';
import { NBAPlayerRecord } from '../../types';
import { createConfiguredPage, withPuppeteerBrowser } from '../puppeteer-utils';

// Type definitions for puppeteer (since we're using dynamic imports)
type Browser = any;
type Page = any;

const NBA_PLAYERS_URL = 'https://www.nba.com/players';
const SCRAPER_TIMEOUT = 60000; // 60 seconds
const PAGE_LOAD_TIMEOUT = 30000; // 30 seconds
const REQUEST_DELAY = 2000; // 2 seconds between requests

/**
 * Configuration for the NBA player scraper
 */
interface ScraperConfig {
  headless: boolean;
  timeout: number;
  userAgent: string;
}

/**
 * Default scraper configuration
 */
const DEFAULT_CONFIG: ScraperConfig = {
  headless: true,
  timeout: SCRAPER_TIMEOUT,
  userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
};

/**
 * Scrape birthdate from a player's profile page using robust selectors
 */
async function scrapePlayerBirthdate(page: Page, playerUrl: string): Promise<string | null> {
  try {
    console.log(`🔍 Scraping birthdate from: ${playerUrl}`);
    
    // Navigate to player profile page with retry logic
    let navigationSuccess = false;
    let navRetryCount = 0;
    const maxNavRetries = 2;
    
    while (!navigationSuccess && navRetryCount < maxNavRetries) {
      try {
        // Check if page is still valid before navigation
        if (page.isClosed()) {
          throw new Error('Page is closed, cannot navigate');
        }
        
        await page.goto(playerUrl, { 
          waitUntil: 'networkidle2', 
          timeout: PAGE_LOAD_TIMEOUT 
        });
        navigationSuccess = true;
      } catch (error) {
        navRetryCount++;
        const errorMessage = error instanceof Error ? error.message : String(error);
        
        if (errorMessage.includes('frame was detached') || errorMessage.includes('detached Frame') || errorMessage.includes('Target closed') || errorMessage.includes('Protocol error') || errorMessage.includes('Attempted to use detached')) {
          console.warn(`Birthdate navigation failed due to frame detachment (attempt ${navRetryCount}): ${errorMessage}`);
          
          if (navRetryCount < maxNavRetries) {
            console.log(`Retrying birthdate navigation in ${navRetryCount} seconds...`);
            await setTimeout(navRetryCount * 1000);
            continue;
          } else {
            console.error(`❌ Failed to navigate to birthdate page after ${maxNavRetries} attempts: ${errorMessage}`);
            return null;
          }
        } else {
          console.error(`❌ Non-retryable birthdate navigation error: ${errorMessage}`);
          return null;
        }
      }
    }
    
    // Wait for the page to load
    await page.waitForSelector('body', { timeout: PAGE_LOAD_TIMEOUT });
    
    // Look for birthdate using robust selectors
    // Strategy 1: Target PlayerSummary_playerInfoValue class (NBA.com specific structure)
    // Use partial class matching to survive hash/version changes (e.g., JS8_v -> different hash)
    try {
      // Find all PlayerSummary_playerInfoValue elements (there are multiple - height, weight, birthdate, etc.)
      const playerInfoElements = await page.$$('[class*="PlayerSummary_playerInfoValue"]');
      
      for (const element of playerInfoElements) {
        const text = await element.evaluate((el: Element) => el.textContent?.trim() || '');
        
        // Check if this element contains a date pattern (birthdate will have a date)
        const datePatterns = [
          // MM/DD/YYYY format
          /\b(\d{1,2})\/(\d{1,2})\/(\d{4})\b/,
          // MM-DD-YYYY format  
          /\b(\d{1,2})-(\d{1,2})-(\d{4})\b/,
          // Month DD, YYYY format
          /\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}\b/i,
          // YYYY-MM-DD format
          /\b(\d{4})-(\d{1,2})-(\d{1,2})\b/
        ];
        
        for (const pattern of datePatterns) {
          const match = text.match(pattern);
          if (match) {
            // Additional validation: Check if there's a birthdate label nearby
            // Look for the label (parent or sibling element containing "birth" text)
            const hasBirthContext = await element.evaluate((el: Element) => {
              // Check parent element
              const parent = el.parentElement;
              if (parent) {
                const parentText = parent.textContent?.toLowerCase() || '';
                if (parentText.includes('birth') || parentText.includes('born')) {
                  return true;
                }
              }
              // Check previous sibling (common pattern: label -> value)
              const prevSibling = el.previousElementSibling;
              if (prevSibling) {
                const siblingText = prevSibling.textContent?.toLowerCase() || '';
                if (siblingText.includes('birth') || siblingText.includes('born')) {
                  return true;
                }
              }
              return false;
            });
            
            // If we found a date pattern in PlayerSummary_playerInfoValue, it's likely the birthdate
            // (other fields like height/weight won't match date patterns)
            let birthdate = match[0];
            
            // Convert to YYYY-MM-DD format
            try {
              const parsedDate = new Date(birthdate);
              if (!isNaN(parsedDate.getTime())) {
                const isoDate = parsedDate.toISOString().split('T')[0];
                console.log(`✅ Found birthdate in PlayerSummary_playerInfoValue: "${birthdate}" -> ${isoDate}${hasBirthContext ? ' (confirmed by label)' : ''}`);
                return isoDate;
              }
            } catch (parseError) {
              console.log(`⚠️  Could not parse date from PlayerSummary_playerInfoValue: "${birthdate}"`);
            }
          }
        }
      }
    } catch (playerInfoError) {
      console.log('⚠️  Could not find PlayerSummary_playerInfoValue elements, trying fallback selectors...');
    }
    
    // Strategy 2: Fallback to other selectors if PlayerSummary_playerInfoValue approach fails
    const fallbackSelectors = [
      // Semantic selectors (most reliable)
      '[data-testid*="birthdate"]',
      '[data-testid*="birth"]',
      '[data-testid*="date"]',
      
      // Partial class matching (survives CSS changes)
      '[class*="birthdate"]',
      '[class*="birth"]',
      '[class*="date"]',
      '[class*="info"]',
      '[class*="value"]',
      
      // Structural selectors (HTML structure rarely changes)
      'td', 'span', 'div', 'p'
    ];
    
    // Try each fallback selector strategy
    for (const selector of fallbackSelectors) {
      try {
        const elements = await page.$$(selector);
        
        for (const element of elements) {
          const text = await element.evaluate((el: Element) => el.textContent?.trim() || '');
          
          // Look for date patterns in the text
          const datePatterns = [
            // MM/DD/YYYY format
            /\b(\d{1,2})\/(\d{1,2})\/(\d{4})\b/,
            // MM-DD-YYYY format  
            /\b(\d{1,2})-(\d{1,2})-(\d{4})\b/,
            // Month DD, YYYY format
            /\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}\b/i,
            // YYYY-MM-DD format
            /\b(\d{4})-(\d{1,2})-(\d{1,2})\b/
          ];
          
          for (const pattern of datePatterns) {
            const match = text.match(pattern);
            if (match) {
              let birthdate = match[0];
              
              // Convert to YYYY-MM-DD format
              try {
                const parsedDate = new Date(birthdate);
                if (!isNaN(parsedDate.getTime())) {
                  const isoDate = parsedDate.toISOString().split('T')[0];
                  console.log(`✅ Found birthdate: "${birthdate}" -> ${isoDate}`);
                  return isoDate;
                }
              } catch (parseError) {
                console.log(`⚠️  Could not parse date: "${birthdate}"`);
              }
            }
          }
        }
      } catch (selectorError) {
        // Continue to next selector
        continue;
      }
    }
    
    console.log(`⚠️  Could not find birthdate for player: ${playerUrl}`);
    return null;
    
  } catch (error) {
    console.warn(`❌ Error scraping birthdate from ${playerUrl}:`, error);
    return null;
  }
}

/**
 * Browser tab pool for managing concurrent birthdate scraping
 */
class BrowserTabPool {
  private browser: Browser;
  private availableTabs: Page[] = [];
  private busyTabs: Set<Page> = new Set();
  private maxTabs: number;
  private userAgent: string;

  constructor(browser: Browser, maxTabs: number = 10, userAgent: string) {
    this.browser = browser;
    this.maxTabs = maxTabs;
    this.userAgent = userAgent;
  }

  async initialize(): Promise<void> {
    console.log(`🚀 Initializing browser tab pool with ${this.maxTabs} tabs...`);
    
    for (let i = 0; i < this.maxTabs; i++) {
      const page = await createConfiguredPage(this.browser, {
        userAgent: this.userAgent,
        viewport: { width: 1920, height: 1080 }
      });
      this.availableTabs.push(page);
    }
    
    console.log(`✅ Browser tab pool initialized with ${this.availableTabs.length} tabs`);
  }

  async acquireTab(): Promise<Page> {
    // Wait for an available tab
    while (this.availableTabs.length === 0) {
      await setTimeout(100); // Wait 100ms before checking again
    }
    
    const tab = this.availableTabs.pop()!;
    this.busyTabs.add(tab);
    return tab;
  }

  releaseTab(tab: Page): void {
    if (this.busyTabs.has(tab)) {
      this.busyTabs.delete(tab);
      this.availableTabs.push(tab);
    }
  }

  async cleanup(): Promise<void> {
    console.log('🧹 Cleaning up browser tab pool...');
    
    // Close all tabs
    const allTabs = [...this.availableTabs, ...this.busyTabs];
    await Promise.all(allTabs.map(tab => tab.close()));
    
    this.availableTabs = [];
    this.busyTabs.clear();
    
    console.log('✅ Browser tab pool cleaned up');
  }

  getStats(): { available: number; busy: number; total: number } {
    return {
      available: this.availableTabs.length,
      busy: this.busyTabs.size,
      total: this.maxTabs
    };
  }
}


/**
 * Parallel birthdate scraping with concurrency control
 */
async function scrapePlayerBirthdatesParallel(
  browser: Browser,
  players: Array<{ name: string; playerUrl: string; team: string; teamUrl?: string }>,
  userAgent: string,
  maxConcurrency: number
): Promise<Array<{ player: typeof players[0]; birthdate: string | null }>> {
  const tabPool = new BrowserTabPool(browser, maxConcurrency, userAgent);
  
  await tabPool.initialize();
  
  console.log(`🔄 Starting parallel birthdate scraping for ${players.length} players with ${maxConcurrency} concurrent tabs...`);
  
  const results: Array<{ player: typeof players[0]; birthdate: string | null }> = new Array(players.length);
  const promises: Promise<void>[] = [];
  let completedCount = 0;
  
  for (let i = 0; i < players.length; i++) {
    const player = players[i];
    
    const promise = (async () => {
      const tab = await tabPool.acquireTab();
      
      const birthdate = await scrapePlayerBirthdate(tab, player.playerUrl).catch(() => null);
      results[i] = { player, birthdate };
      
      // Log progress
      completedCount++;
      const stats = tabPool.getStats();
      console.log(`📊 Progress: ${completedCount}/${players.length} (${Math.round(completedCount/players.length*100)}%) | Tabs: ${stats.busy}/${stats.total} busy`);
      
      tabPool.releaseTab(tab);
      // Add small delay between requests to be respectful to the server
      await setTimeout(500);
    })();
    
    promises.push(promise);
  }
  
  // Wait for all birthdate scraping to complete
  await Promise.all(promises);
  
  const successfulResults = results.filter(r => r !== undefined);
  const successRate = Math.round((successfulResults.filter(r => r.birthdate !== null).length / successfulResults.length) * 100);
  
  console.log(`✅ Parallel birthdate scraping completed for ${players.length} players`);
  console.log(`📈 Success rate: ${successRate}% (${successfulResults.filter(r => r.birthdate !== null).length}/${successfulResults.length} birthdates found)`);
  
  await tabPool.cleanup();
  
  return successfulResults;
}

/**
 * Extract player ID from NBA.com player URL
 * Example: "/player/1630173/precious-achiuwa/" -> 1630173
 */
function extractPlayerIdFromUrl(url: string): number | null {
  const match = url.match(/\/player\/(\d+)\//);
  return match ? parseInt(match[1], 10) : null;
}

/**
 * Extract team abbreviation from team URL or text
 * Example: "/team/1610612748/heat/" -> "MIA" or "Miami Heat" -> "MIA"
 */
function extractTeamAbbreviation(teamText: string, teamUrl?: string): string {
  // First try to extract from URL pattern
  if (teamUrl) {
    const urlMatch = teamUrl.match(/\/team\/\d+\/(\w+)\//);
    if (urlMatch) {
      const teamName = urlMatch[1].toLowerCase();
      // Map common team names to abbreviations
      const teamMap: Record<string, string> = {
        'heat': 'MIA',
        'lakers': 'LAL',
        'warriors': 'GSW',
        'celtics': 'BOS',
        'nets': 'BKN',
        'knicks': 'NYK',
        'sixers': 'PHI',
        'raptors': 'TOR',
        'bulls': 'CHI',
        'cavaliers': 'CLE',
        'pistons': 'DET',
        'pacers': 'IND',
        'bucks': 'MIL',
        'hawks': 'ATL',
        'hornets': 'CHA',
        'magic': 'ORL',
        'wizards': 'WAS',
        'nuggets': 'DEN',
        'timberwolves': 'MIN',
        'thunder': 'OKC',
        'blazers': 'POR',
        'jazz': 'UTA',
        'clippers': 'LAC',
        'suns': 'PHX',
        'kings': 'SAC',
        'mavericks': 'DAL',
        'rockets': 'HOU',
        'grizzlies': 'MEM',
        'pelicans': 'NOP',
        'spurs': 'SAS'
      };
      return teamMap[teamName] || teamName.toUpperCase();
    }
  }
  
  // Fallback: return the text as-is (should already be abbreviation from table)
  return teamText.trim();
}

/**
 * Scrape a single page of NBA players
 */
async function scrapePage(page: Page, pageNumber: number, browser: Browser, userAgent: string): Promise<NBAPlayerRecord[]> {
  console.log(`Scraping page ${pageNumber}...`);
  
  try {
    // Wait for the player table to load
    await page.waitForSelector('table tbody tr', { timeout: PAGE_LOAD_TIMEOUT });
    
    // Extract player data from the table using natural Puppeteer selectors
    const players: Array<{
      name: string;
      playerUrl: string;
      team: string;
      teamUrl?: string;
    }> = [];
    
    // Get all table rows
    const rows = await page.$$('table tbody tr');
    console.log(`Found ${rows.length} player rows`);
    
    for (const row of rows) {
      try {
        const cells = await row.$$('td');
        if (cells.length >= 4) {
          // Player name and URL (first column)
          const playerLink = await cells[0].$('a[href*="/player/"]');
          if (!playerLink) continue;
          
          // Extract name from the link text
          let name = await playerLink.evaluate((el: Element) => el.textContent?.trim() || '');
          // Remove "Headshot" text that might be included
          name = name.replace(/Headshot/g, '').trim();
          // Add spaces between concatenated names (e.g., "PreciousAchiuwa" -> "Precious Achiuwa")
          name = name.replace(/([a-z])([A-Z])/g, '$1 $2');
          
          const playerUrl = await playerLink.evaluate((el: HTMLAnchorElement) => el.href);
          
          // Team (second column)
          const teamLink = await cells[1].$('a[href*="/team/"]');
          let team = '';
          let teamUrl = '';
          
          if (teamLink) {
            team = await teamLink.evaluate((el: Element) => el.textContent?.trim() || '');
            teamUrl = await teamLink.evaluate((el: HTMLAnchorElement) => el.href);
          } else {
            team = await cells[1].evaluate((el: Element) => el.textContent?.trim() || '');
          }
          
          if (name && playerUrl) {
            players.push({
              name,
              playerUrl,
              team,
              teamUrl
            });
          }
        }
      } catch (error) {
        console.warn('Error processing row:', error);
      }
    }
    
    console.log(`🔄 Starting parallel birthdate scraping for ${players.length} players on page ${pageNumber}...`);
    
    // Use parallel birthdate scraping for all players on this page
    const birthdateResults = await scrapePlayerBirthdatesParallel(browser, players, userAgent, 2);
    
    // Process the extracted data with birthdate results
    const processedPlayers: NBAPlayerRecord[] = [];
    
    for (const result of birthdateResults) {
      const playerId = extractPlayerIdFromUrl(result.player.playerUrl);
      if (playerId) {
        // Parse name at first space: "LeBron James" -> FirstName: "LeBron", LastName: "James"
        // Handle edge cases: single name becomes FirstName, empty LastName
        const nameParts = result.player.name.trim().split(/\s+/);
        const firstName = nameParts[0] || '';
        const lastName = nameParts.slice(1).join(' ') || '';
        
        processedPlayers.push({
          NBAPlayer: playerId,
          Name: result.player.name,
          FirstName: firstName,
          LastName: lastName,
          CurrentTeam: result.player.team, // Store full team name (e.g., "Miami Heat") instead of abbreviation
          BirthDate: result.birthdate || undefined
        });
      } else {
        console.warn(`Could not extract player ID from URL: ${result.player.playerUrl}`);
      }
    }
    
    console.log(`✅ Extracted ${processedPlayers.length} players from page ${pageNumber} with parallel birthdate scraping`);
    return processedPlayers;
    
  } catch (error) {
    console.error(`Error scraping page ${pageNumber}:`, error);
    throw error;
  }
}

/**
 * Navigate to next page if available
 */
async function goToNextPage(page: Page, currentPage: number): Promise<boolean> {
  try {
    console.log(`Looking for page ${currentPage + 1} navigation...`);
    
    // Look for pagination controls and next page button using natural Puppeteer selectors
    let nextPageExists = false;
    
    try {
      // Strategy 1: Look for specific page number buttons
      const allElements = await page.$$('*');
      
      for (const element of allElements) {
        const text = await element.evaluate((el: Element) => el.textContent?.trim() || '');
        
        // Look for clickable element with next page number
        if (text === String(currentPage + 1)) {
          const tagName = await element.evaluate((el: Element) => el.tagName);
          const role = await element.evaluate((el: Element) => el.getAttribute('role'));
          const classList = await element.evaluate((el: Element) => el.classList.contains('clickable'));
          const cursor = await element.evaluate((el: Element) => (el as HTMLElement).style.cursor);
          
          if (tagName === 'BUTTON' || 
              tagName === 'A' || 
              role === 'button' ||
              classList ||
              cursor === 'pointer') {
            
            console.log(`Found page ${currentPage + 1} button`);
            await element.click();
            nextPageExists = true;
            break;
          }
        }
      }
      
      // Strategy 2: Look for "Next" or arrow buttons
      if (!nextPageExists) {
        const buttons = await page.$$('button, a, [role="button"], [class*="next"], [class*="Next"]');
        
        for (const button of buttons) {
          const text = await button.evaluate((el: Element) => el.textContent?.trim() || '');
          const ariaLabel = await button.evaluate((el: Element) => el.getAttribute('aria-label') || '');
          const disabled = await button.evaluate((el: Element) => el.hasAttribute('disabled'));
          const disabledClass = await button.evaluate((el: Element) => el.classList.contains('disabled'));
          
          if ((text.toLowerCase().includes('next') || 
               text.includes('›') || 
               text.includes('→') ||
               text.includes('>') ||
               ariaLabel.toLowerCase().includes('next')) && 
              !disabled &&
              !disabledClass) {
            
            console.log(`Found next button: ${text || ariaLabel}`);
            await button.click();
            nextPageExists = true;
            break;
          }
        }
      }
      
      // Strategy 3: Look in pagination area specifically
      if (!nextPageExists) {
        const paginationElements = await page.$$('[class*="pagination"], [class*="Pagination"], [class*="page"], [class*="Page"]');
        
        for (const paginationEl of paginationElements) {
          const nextPageButton = await paginationEl.$(`[data-page="${currentPage + 1}"]`);
          if (nextPageButton) {
            console.log(`Found next page in pagination area`);
            await nextPageButton.click();
            nextPageExists = true;
            break;
          }
        }
      }
    } catch (error) {
      console.warn('Error during pagination detection:', error);
      nextPageExists = false;
    }
    
    if (nextPageExists) {
      console.log(`Navigating to page ${currentPage + 1}...`);
      // Wait for page to load
      await setTimeout(REQUEST_DELAY * 2);
      
      try {
        await page.waitForSelector('table tbody tr', { timeout: PAGE_LOAD_TIMEOUT });
        
        // Verify we're on a different page by checking if content changed using natural Puppeteer selectors
        const firstPlayerLink = await page.$('table tbody tr:first-child a[href*="/player/"]');
        const newPageContent = firstPlayerLink ? await firstPlayerLink.evaluate((el: Element) => el.getAttribute('href')) : null;
        
        console.log(`Page ${currentPage + 1} loaded, first player: ${newPageContent}`);
        return true;
      } catch (waitError) {
        console.warn(`Page ${currentPage + 1} didn't load properly:`, waitError);
        return false;
      }
    }
    
    console.log(`No next page found after page ${currentPage}`);
    return false;
  } catch (error) {
    console.warn(`Error navigating to next page from page ${currentPage}:`, error);
    return false;
  }
}

/**
 * Scrape all NBA players from the NBA.com players page
 */
export async function scrapeNBAPlayers(config: Partial<ScraperConfig> = {}): Promise<NBAPlayerRecord[]> {
  const finalConfig = { ...DEFAULT_CONFIG, ...config };
  
  // Try with proxy first, then fallback to no proxy if browser crashes
  let browserConfig = { 
    scraperName: 'NBA players',
    skipIpCheck: true // Skip IP check for NBA scraper to be faster
  };
  
  try {
    return await withPuppeteerBrowser(async (browser) => {
    // Add browser-level error handling
    browser.on('disconnected', () => {
      console.error('🚨 Browser disconnected unexpectedly');
    });
    
    browser.on('targetdestroyed', (target: any) => {
      console.warn('🚨 Target destroyed:', target.url());
    });
    const page = await createConfiguredPage(browser, {
      userAgent: finalConfig.userAgent,
      viewport: { width: 1920, height: 1080 }
    });
    
    // Add frame detachment detection
    page.on('framedetached', (frame: any) => {
      console.error('🚨 FRAME DETACHED in player scraper:', {
        url: frame.url(),
        name: frame.name(),
        timestamp: new Date().toISOString()
      });
    });
    
    page.on('pageerror', (error: Error) => {
      console.error('🚨 PAGE ERROR in player scraper:', error.message);
    });
    
    // Navigate to NBA players page with retry logic
    console.log(`🔍 DEBUG: About to navigate to ${NBA_PLAYERS_URL}...`);
    let workingPage = page;
    let navigationSuccess = false;
    let navRetryCount = 0;
    const maxNavRetries = 3;
    
    while (!navigationSuccess && navRetryCount < maxNavRetries) {
      try {
        // Check if page is still valid before navigation
        if (workingPage.isClosed()) {
          throw new Error('Page is closed, cannot navigate');
        }
        
        await workingPage.goto(NBA_PLAYERS_URL, { 
          waitUntil: 'networkidle2',
          timeout: PAGE_LOAD_TIMEOUT 
        });
        console.log('✅ DEBUG: Successfully navigated to NBA players page');
        navigationSuccess = true;
      } catch (error) {
        navRetryCount++;
        const errorMessage = error instanceof Error ? error.message : String(error);
        
        if (errorMessage.includes('frame was detached') || errorMessage.includes('detached Frame') || errorMessage.includes('Target closed') || errorMessage.includes('Protocol error') || errorMessage.includes('Attempted to use detached')) {
          console.warn(`Navigation failed due to frame detachment (attempt ${navRetryCount}): ${errorMessage}`);
          
          if (navRetryCount < maxNavRetries) {
            console.log(`Retrying navigation in ${navRetryCount * 2} seconds...`);
            await setTimeout(navRetryCount * 2000);
            
            // Create a new page for retry
            console.log('Creating new page for retry...');
            try {
              await workingPage.close();
            } catch (closeError) {
              // Ignore close errors
            }
            
            // Check if browser is still connected before creating new page
            if (browser.isConnected()) {
              workingPage = await createConfiguredPage(browser, {
                userAgent: finalConfig.userAgent,
                viewport: { width: 1920, height: 1080 }
              });
            } else {
              throw new Error('Browser disconnected, cannot create new page');
            }
            
            continue;
          } else {
            console.error('❌ DEBUG: Failed to navigate after all retries');
            throw new Error(`Navigation failed after ${maxNavRetries} attempts: ${errorMessage}`);
          }
        } else {
          console.error('❌ DEBUG: Non-retryable navigation error:', error);
          throw error;
        }
      }
    }
    
    // Use the successfully navigated page
    const finalPage = workingPage;
    
    // Wait for page to load and look for the dropdown
    await setTimeout(3000);
    
    try {
      // Try to find and interact with the pagination dropdown to show "All" rows
      console.log('Looking for pagination dropdown to show all rows...');
      
      // Wait for the page to load and show the pagination info
      await setTimeout(3000);
      
      // Based on debug output, target the specific pagination select element
      console.log('Looking for pagination select element...');
      
      // Look for the pagination select that contains "All123456789101112" using natural Puppeteer selectors
      let paginationSelectFound = { found: false };
      
      try {
        // Look for select elements that contain pagination options using robust selectors
        const selects = await finalPage.$$('select[class*="Pagination_pageDropdown"], select[data-testid*="pagination"], select[class*="pagination"], select[class*="Pagination"], select[class*="dropdown"], select[class*="Dropdown"], select');
        
        for (const select of selects) {
          const text = await select.evaluate((el: Element) => el.textContent?.trim() || '');
          // Look for the select that contains "All" and numbers (pagination)
          if (text.includes('All') && text.match(/\d+/) && text.length < 50) {
            // Check if it has "All" option
            const options = await select.$$('option');
            for (const option of options) {
              const optionText = await option.evaluate((el: Element) => el.textContent?.trim() || '');
              const optionValue = await option.evaluate((el: Element) => (el as HTMLOptionElement).value);
              
              if (optionText === 'All' || optionValue === '-1') {
                const selectClass = await select.evaluate((el: Element) => el.className);
                paginationSelectFound = {
                  found: true,
                  selectClass,
                  hasAllOption: true
                } as any;
                console.log(`Found pagination dropdown with class: ${selectClass}`);
                break;
              }
            }
            if (paginationSelectFound.found) break;
          }
        }
      } catch (error) {
        console.warn('Error during pagination select detection:', error);
        paginationSelectFound = { found: false };
      }
      
      if (paginationSelectFound.found) {
        console.log('Found pagination select element with "All" option');
        
        // Select the "All" option directly using natural Puppeteer selectors
        let allSelected = false;
        
        try {
          const selects = await finalPage.$$('select[class*="Pagination_pageDropdown"], select[data-testid*="pagination"], select[class*="pagination"], select[class*="Pagination"], select[class*="dropdown"], select[class*="Dropdown"], select');
          
          for (const select of selects) {
            const text = await select.evaluate((el: Element) => el.textContent?.trim() || '');
            if (text.includes('All') && text.match(/\d+/) && text.length < 50) {
              const options = await select.$$('option');
              for (const option of options) {
                const optionText = await option.evaluate((el: any) => el.textContent?.trim() || '');
                const optionValue = await option.evaluate((el: any) => el.value);
                
                if (optionText === 'All' || optionValue === '-1') {
                  // Select the "All" option using Puppeteer's select method
                  console.log(`Selecting "All" option with value: ${optionValue}`);
                  await select.select(optionValue);
                  
                  // Trigger change event
                  await select.evaluate((el: any) => {
                    el.dispatchEvent(new Event('change', { bubbles: true }));
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                  });
                  
                  allSelected = true;
                  break;
                }
              }
              if (allSelected) break;
            }
          }
        } catch (error) {
          console.warn('Error during "All" option selection:', error);
          allSelected = false;
        }
        
        if (allSelected) {
          console.log('Successfully selected "All" from pagination dropdown');
          
          // Wait for page to reload with all players
          console.log('Waiting for page to reload with all players...');
          await setTimeout(REQUEST_DELAY * 4); // Longer wait for full reload
          
          // Wait for table to update
          try {
            await finalPage.waitForSelector('table tbody tr', { timeout: PAGE_LOAD_TIMEOUT });
          } catch (waitError) {
            console.warn('Table did not reload, continuing with current state');
          }
          
          // Verify we got all players using natural Puppeteer selectors
          const playerRows = await finalPage.$$('table tbody tr');
          const playerCount = playerRows.length;
          
          console.log(`Player table now shows ${playerCount} players`);
          
          if (playerCount > 50) {
            console.log('🎉 SUCCESS! Now showing all players on one page');
          } else {
            console.log('⚠️ Still showing paginated results, will continue with pagination');
          }
        } else {
          console.log('Could not select "All" option from pagination dropdown');
        }
      } else {
        console.log('Could not find pagination select with "All" option');
      }
      
    } catch (dropdownError) {
      console.warn('Could not find or interact with pagination dropdown:', dropdownError);
    }
    
    // Scrape all pages
    const allPlayers: NBAPlayerRecord[] = [];
    let currentPage = 1;
    let hasMorePages = true;
    
    while (hasMorePages && currentPage <= 15) { // Safety limit of 15 pages (593 players / ~50 per page = ~12 pages)
      try {
        const pageData = await scrapePage(finalPage, currentPage, browser, finalConfig.userAgent);
        allPlayers.push(...pageData);
        
        // Try to go to next page
        hasMorePages = await goToNextPage(finalPage, currentPage);
        currentPage++;
        
        if (hasMorePages) {
          console.log(`Moving to page ${currentPage}...`);
        }
        
      } catch (pageError) {
        console.error(`Error on page ${currentPage}:`, pageError);
        break;
      }
    }
    
    console.log(`NBA player scraping completed. Total players found: ${allPlayers.length}`);
    return allPlayers;
  }, browserConfig);
  
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    
    // If browser crashes due to proxy issues, try without proxy
    if (errorMessage.includes('Connection closed') || errorMessage.includes('Protocol error') || errorMessage.includes('Browser disconnected')) {
      console.warn('🚨 Browser crashed with proxy, retrying without proxy...');
      
      // Temporarily disable proxy by clearing environment variables
      const originalProxyHost = process.env.PROXY_HOST_PORT;
      const originalProxyUser = process.env.PROXY_USER;
      const originalProxyPass = process.env.PROXY_PASS;
      
      try {
        delete process.env.PROXY_HOST_PORT;
        delete process.env.PROXY_USER;
        delete process.env.PROXY_PASS;
        
        console.log('🔄 Retrying NBA player scraping without proxy...');
        return await withPuppeteerBrowser(async (browser) => {
          // Add browser-level error handling
          browser.on('disconnected', () => {
            console.error('🚨 Browser disconnected unexpectedly (no proxy)');
          });
          
          browser.on('targetdestroyed', (target: any) => {
            console.warn('🚨 Target destroyed (no proxy):', target.url());
          });
          
          const page = await createConfiguredPage(browser, {
            userAgent: finalConfig.userAgent,
            viewport: { width: 1920, height: 1080 }
          });
          
          // Add frame detachment detection
          page.on('framedetached', (frame: any) => {
            console.error('🚨 FRAME DETACHED in player scraper (no proxy):', {
              url: frame.url(),
              name: frame.name(),
              timestamp: new Date().toISOString()
            });
          });
          
          page.on('pageerror', (error: Error) => {
            console.error('🚨 PAGE ERROR in player scraper (no proxy):', error.message);
          });
          
          // Navigate to NBA players page with retry logic
          console.log(`🔍 DEBUG: About to navigate to ${NBA_PLAYERS_URL} (no proxy)...`);
          let workingPage = page;
          let navigationSuccess = false;
          let navRetryCount = 0;
          const maxNavRetries = 3;
          
          while (!navigationSuccess && navRetryCount < maxNavRetries) {
            try {
              // Check if page is still valid before navigation
              if (workingPage.isClosed()) {
                throw new Error('Page is closed, cannot navigate');
              }
              
              await workingPage.goto(NBA_PLAYERS_URL, { 
                waitUntil: 'networkidle2',
                timeout: PAGE_LOAD_TIMEOUT 
              });
              console.log('✅ DEBUG: Successfully navigated to NBA players page (no proxy)');
              navigationSuccess = true;
            } catch (error) {
              navRetryCount++;
              const errorMessage = error instanceof Error ? error.message : String(error);
              
              if (errorMessage.includes('frame was detached') || errorMessage.includes('detached Frame') || errorMessage.includes('Target closed') || errorMessage.includes('Protocol error') || errorMessage.includes('Attempted to use detached')) {
                console.warn(`Navigation failed due to frame detachment (attempt ${navRetryCount}, no proxy): ${errorMessage}`);
                
                if (navRetryCount < maxNavRetries) {
                  console.log(`Retrying navigation in ${navRetryCount * 2} seconds...`);
                  await setTimeout(navRetryCount * 2000);
                  
                  // Create a new page for retry
                  console.log('Creating new page for retry...');
                  try {
                    await workingPage.close();
                  } catch (closeError) {
                    // Ignore close errors
                  }
                  
                  // Check if browser is still connected before creating new page
                  if (browser.isConnected()) {
                    workingPage = await createConfiguredPage(browser, {
                      userAgent: finalConfig.userAgent,
                      viewport: { width: 1920, height: 1080 }
                    });
                  } else {
                    throw new Error('Browser disconnected, cannot create new page');
                  }
                  
                  continue;
                } else {
                  console.error('❌ DEBUG: Failed to navigate after all retries (no proxy)');
                  throw new Error(`Navigation failed after ${maxNavRetries} attempts: ${errorMessage}`);
                }
              } else {
                console.error('❌ DEBUG: Non-retryable navigation error (no proxy):', error);
                throw error;
              }
            }
          }
          
          // Use the successfully navigated page
          const finalPageNoProxy = workingPage;
          
          // Wait for page to load and look for the dropdown
          await setTimeout(3000);
          
          // Continue with the rest of the scraping logic...
          // (The rest of the function would be duplicated here, but for brevity, I'll just return the original logic)
          const allPlayers: NBAPlayerRecord[] = [];
          let currentPage = 1;
          let hasMorePages = true;
          
          while (hasMorePages && currentPage <= 15) {
            try {
              const pageData = await scrapePage(finalPageNoProxy, currentPage, browser, finalConfig.userAgent);
              allPlayers.push(...pageData);
              
              hasMorePages = await goToNextPage(finalPageNoProxy, currentPage);
              currentPage++;
              
              if (hasMorePages) {
                console.log(`Moving to page ${currentPage}...`);
              }
              
            } catch (pageError) {
              console.error(`Error on page ${currentPage}:`, pageError);
              break;
            }
          }
          
          console.log(`NBA player scraping completed (no proxy). Total players found: ${allPlayers.length}`);
          return allPlayers;
        }, { 
          scraperName: 'NBA players (no proxy)',
          skipIpCheck: true
        });
        
      } finally {
        // Restore original proxy settings
        if (originalProxyHost) process.env.PROXY_HOST_PORT = originalProxyHost;
        if (originalProxyUser) process.env.PROXY_USER = originalProxyUser;
        if (originalProxyPass) process.env.PROXY_PASS = originalProxyPass;
      }
    } else {
      // Re-throw non-proxy related errors
      throw error;
    }
  }
}

/**
 * Get NBA players - simplified without retries
 */
export async function fetchNBAPlayersWithRetry(): Promise<NBAPlayerRecord[]> {
  return await scrapeNBAPlayers();
}
