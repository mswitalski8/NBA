// Dynamic puppeteer import - will be loaded at runtime based on environment

// Type definitions for puppeteer (since we're using dynamic imports)
type Browser = any;
type Page = any;
import { setTimeout } from 'node:timers/promises';
import { NBATransaction } from '../../types';
import { createConfiguredPage, withPuppeteerBrowser } from '../puppeteer-utils';

const NBA_TRANSACTIONS_URL = 'https://www.nba.com/players/transactions';
const SCRAPER_TIMEOUT = 60000; // 60 seconds
const PAGE_LOAD_TIMEOUT = 30000; // 30 seconds
const REQUEST_DELAY = 2000; // 2 seconds between requests

/**
 * Configuration for the NBA transaction scraper
 */
interface TransactionScraperConfig {
  headless: boolean;
  timeout: number;
  userAgent: string;
  daysToScrape?: number; // Number of recent days to scrape (default: 1)
  targetDate?: string; // Specific date to scrape in YYYY-MM-DD format
}

/**
 * Default scraper configuration
 */
const DEFAULT_CONFIG: TransactionScraperConfig = {
  headless: true,
  timeout: SCRAPER_TIMEOUT,
  userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  daysToScrape: 1
};

/**
 * Raw transaction data extracted from the page
 */
interface RawTransactionData {
  date: string;
  description: string;
}

/**
 * Parse player names from transaction description
 * Refined to handle actual NBA transaction formats
 */
function parsePlayerNamesFromDescription(description: string): string[] {
  const playerNames: string[] = [];
  
  // Common NBA transaction patterns:
  // "Team signed guard Player Name to a Contract"
  // "Team waived forward Player Name"
  // "Team converted the contract of guard Player Name to a Two-Way Contract"
  // "Team re-signed forward Player Name to a Extension"
  
  // Pattern 1: "Team [action] [position] Player Name [to/.]"
  const teamActionMatch = description.match(/(?:signed|waived|converted|re-signed)\s+(?:guard|forward|center)?\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*?)(?:\s+to|\s*\.|$)/i);
  if (teamActionMatch) {
    let playerName = teamActionMatch[1].trim();
    // Clean up common suffixes that aren't part of names
    playerName = playerName.replace(/\s+(to|Jr\.|Sr\.|III|II|IV)$/, ' $1').trim();
    if (playerName && !playerName.match(/^(contract|extension|two-way)$/i)) {
      playerNames.push(playerName);
    }
  }
  
  // Pattern 2: "converted the contract of [position] Player Name"
  const convertedMatch = description.match(/converted\s+the\s+contract\s+of\s+(?:guard|forward|center)?\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*?)(?:\s+to|\s*\.|$)/i);
  if (convertedMatch) {
    let playerName = convertedMatch[1].trim();
    playerName = playerName.replace(/\s+(to|Jr\.|Sr\.|III|II|IV)$/, ' $1').trim();
    if (playerName && !playerName.match(/^(contract|extension|two-way)$/i)) {
      playerNames.push(playerName);
    }
  }
  
  // Pattern 3: Handle names with Jr., Sr., III, etc.
  const juniorMatch = description.match(/(?:signed|waived|converted|re-signed)\s+(?:guard|forward|center)?\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*?\s+(?:Jr\.|Sr\.|III|II|IV))/i);
  if (juniorMatch) {
    playerNames.push(juniorMatch[1].trim());
  }
  
  // Pattern 4: Handle trade descriptions "received [position] Player Name from"
  const tradeMatch = description.match(/received\s+(?:guard|forward|center)?\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*?(?:\s+(?:Jr\.|Sr\.|III|II|IV))?)\s+from/i);
  if (tradeMatch) {
    let playerName = tradeMatch[1].trim();
    if (playerName && !playerName.match(/^(contract|extension|two-way)$/i)) {
      playerNames.push(playerName);
    }
  }
  
  // Remove duplicates and filter out invalid names
  const validNames = [...new Set(playerNames)].filter(name => {
    // Filter out team names, positions, and common words
    const invalidWords = /^(guard|forward|center|contract|extension|two-way|the|of|to|a|an)$/i;
    return name.length > 2 && !invalidWords.test(name);
  });
  
  return validNames;
}

/**
 * Parse team names from transaction description and assign correctly based on transaction type
 */
function parseTeamsFromDescription(description: string, transactionType: string): { fromTeam?: string; toTeam?: string } {
  const teams: { fromTeam?: string; toTeam?: string } = {};
  
  // NBA team name patterns - extract team at the beginning of description
  // "Boston Celtics waived forward..."
  // "Sacramento Kings re-signed forward..."
  // "Milwaukee Bucks signed forward..."
  
  const nbaTeams = [
    'Atlanta Hawks', 'Boston Celtics', 'Brooklyn Nets', 'Charlotte Hornets', 'Chicago Bulls',
    'Cleveland Cavaliers', 'Dallas Mavericks', 'Denver Nuggets', 'Detroit Pistons', 'Golden State Warriors',
    'Houston Rockets', 'Indiana Pacers', 'LA Clippers', 'Los Angeles Lakers', 'Memphis Grizzlies',
    'Miami Heat', 'Milwaukee Bucks', 'Minnesota Timberwolves', 'New Orleans Pelicans', 'New York Knicks',
    'Oklahoma City Thunder', 'Orlando Magic', 'Philadelphia 76ers', 'Phoenix Suns', 'Portland Trail Blazers',
    'Sacramento Kings', 'San Antonio Spurs', 'Toronto Raptors', 'Utah Jazz', 'Washington Wizards'
  ];
  
  // Find the primary team (usually at the beginning of the description)
  let primaryTeam: string | undefined;
  for (const team of nbaTeams) {
    if (description.startsWith(team)) {
      primaryTeam = team;
      break;
    }
  }
  
  // Look for "from [Team A] to [Team B]" pattern (for trades)
  const tradeMatch = description.match(/from\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+to\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/i);
  if (tradeMatch) {
    teams.fromTeam = tradeMatch[1].trim();
    teams.toTeam = tradeMatch[2].trim();
    return teams; // For trades, use the explicit from/to pattern
  }
  
  // Look for "received...from [Team]" pattern (common trade format)
  const receivedFromMatch = description.match(/received\s+.*?\s+from\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/i);
  if (receivedFromMatch && primaryTeam) {
    const fromTeamName = receivedFromMatch[1].trim();
    if (nbaTeams.includes(fromTeamName)) {
      teams.fromTeam = fromTeamName;
      teams.toTeam = primaryTeam;
      return teams;
    }
  }
  
  // Look for "by [Team]" pattern (alternative format)
  if (!primaryTeam) {
    const byTeamMatch = description.match(/by\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/i);
    if (byTeamMatch) {
      const teamName = byTeamMatch[1].trim();
      if (nbaTeams.includes(teamName)) {
        primaryTeam = teamName;
      }
    }
  }
  
  // Assign teams based on transaction type
  if (primaryTeam) {
    switch (transactionType.toLowerCase()) {
      case 'waived':
      case 'released':
        // When waived/released: fromTeam = team that waived them, toTeam = N/A
        teams.fromTeam = primaryTeam;
        teams.toTeam = undefined;
        break;
        
      case 'signed':
      case 'claimed':
      case 'assigned':
      case 'recalled':
        // When signed/claimed: fromTeam = N/A, toTeam = team that signed them
        teams.fromTeam = undefined;
        teams.toTeam = primaryTeam;
        break;
        
      case 'traded':
        // For trades without explicit from/to, we need more context
        // Default to toTeam for now
        teams.toTeam = primaryTeam;
        break;
        
      default:
        // For other transaction types, default to toTeam
        teams.toTeam = primaryTeam;
        break;
    }
  }
  
  return teams;
}

/**
 * Determine transaction type from description
 */
function parseTransactionType(description: string): string {
  const lowerDesc = description.toLowerCase();
  
  if (lowerDesc.includes('signed')) return 'Signed';
  if (lowerDesc.includes('waived')) return 'Waived';
  if (lowerDesc.includes('traded')) return 'Traded';
  if (lowerDesc.includes('released')) return 'Released';
  if (lowerDesc.includes('claimed')) return 'Claimed';
  if (lowerDesc.includes('assigned')) return 'Assigned';
  if (lowerDesc.includes('recalled')) return 'Recalled';
  
  return 'Other';
}

/**
 * Scrape NBA transactions from the transactions page
 */
async function scrapeTransactionsFromPage(page: Page, daysToScrape: number, targetDate?: string): Promise<RawTransactionData[]> {
  console.log(`Scraping NBA transactions for the last ${daysToScrape} day(s)...`);
  if (targetDate) {
    console.log(`Filtering for specific date: ${targetDate}`);
  }
  
  try {
    // Enhanced frame detachment protection
    const isPageValid = () => {
      try {
        return !page.isClosed() && page.url() !== 'about:blank';
      } catch {
        return false;
      }
    };
    
    if (!isPageValid()) {
      throw new Error('Page is closed or invalid before scraping');
    }
    
    // Wait for the transaction content to load - try multiple selectors with frame protection
    try {
      // Wait for transaction day containers using more robust selectors
      await page.waitForSelector('[data-testid*="day"], [class*="day"], [class*="Day"]', { timeout: PAGE_LOAD_TIMEOUT });
    } catch (error) {
      console.warn('Primary selector failed, trying fallback:', error);
      
      // Check if page is still valid before fallback
      if (!isPageValid()) {
        throw new Error('Page became invalid during selector wait');
      }
      
      // Fallback: wait for any transaction-related content using semantic selectors
      await page.waitForSelector('[data-testid*="transaction"], [class*="transaction"], [class*="Transaction"], [class*="desc"]', { timeout: PAGE_LOAD_TIMEOUT });
    }
    
    // Extract ALL transaction data first, then filter in Node.js context using natural Puppeteer selectors
    const allTransactions: Array<{ date: string; description: string }> = [];
    
    // Find all transaction day containers using robust selectors with frame protection
    let dayContainers;
    try {
      // Check page validity before querying elements
      if (!isPageValid()) {
        throw new Error('Page became invalid before element query');
      }
      
      dayContainers = await page.$$('[data-testid*="day"], [class*="day"], [class*="Day"]');
      console.log(`🔍 Found ${dayContainers.length} day containers on the page`);
      
      // Verify elements are still attached
      if (dayContainers.length === 0) {
        console.warn('No day containers found, trying alternative selectors...');
        dayContainers = await page.$$('[data-testid*="transaction"], [class*="transaction"], [class*="Transaction"]');
        console.log(`🔍 Found ${dayContainers.length} alternative containers on the page`);
      }
      
    } catch (elementError) {
      console.error('Error querying day containers:', elementError);
      if (!isPageValid()) {
        throw new Error('Page became invalid during element query');
      }
      throw elementError;
    }
    
    // CRITICAL BUSINESS LOGIC: Validate that the most recent date is not older than yesterday
    if (targetDate && dayContainers.length > 0) {
      console.log(`🔍 Validating that most recent transaction date is not older than target date: ${targetDate}`);
      
      try {
        // Get the first (most recent) day container to check its date
        const firstDayContainer = dayContainers[0];
        const headerElement = await firstDayContainer.$('[data-testid*="header"], [class*="header"], [class*="Header"], h1, h2, h3, h4, h5, h6');
        let mostRecentDateText = '';
        
        if (headerElement) {
          mostRecentDateText = await headerElement.evaluate((el: Element) => el.textContent?.trim() || '');
        } else {
          // Fallback: extract date from container text
          const allText = await firstDayContainer.evaluate((el: Element) => el.textContent || '');
          const properDateMatch = allText.match(/\b(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),?\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}\b/i);
          if (properDateMatch) {
            mostRecentDateText = properDateMatch[0];
          } else {
            const malformedDateMatch = allText.match(/\b(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),?\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2}\d{4}\b/i);
            if (malformedDateMatch) {
              mostRecentDateText = malformedDateMatch[0].replace(/(\d{1,2})(\d{4})/, '$1, $2');
            }
          }
        }
        
        if (mostRecentDateText) {
          // Clean and parse the most recent date
          let cleanedDate = mostRecentDateText;
          cleanedDate = cleanedDate.replace(/(\d{1,2})(\d{4})/, '$1, $2');
          cleanedDate = cleanedDate.replace(/(January|February|March|April|May|June|July|August|September|October|November|December)(\d{1,2})/, '$1 $2');
          cleanedDate = cleanedDate.replace(/, (January|February|March|April|May|June|July|August|September|October|November|December)(\d{1,2})(\d{4})/, ', $1 $2, $3');
          cleanedDate = cleanedDate.replace(/(January|February|March|April|May|June|July|August|September|October|November|December)(\d{1,2})(\d{4})/, '$1 $2, $3');
          cleanedDate = cleanedDate.replace(/,([A-Za-z])/, ', $1');
          cleanedDate = cleanedDate.replace(/,(\d{4})/, ', $1');
          
          try {
            const mostRecentDate = new Date(cleanedDate);
            const mostRecentISO = mostRecentDate.toISOString().split('T')[0];
            const targetDateObj = new Date(targetDate);
            const targetISO = targetDateObj.toISOString().split('T')[0];
            
            console.log(`📅 Most recent transaction date: "${mostRecentDateText}" -> ${mostRecentISO}`);
            console.log(`📅 Target date: ${targetISO}`);
            
            // If most recent date is older than target date, return empty results
            if (mostRecentISO < targetISO) {
              console.log(`⚠️  Most recent transaction date (${mostRecentISO}) is older than target date (${targetISO})`);
              console.log(`🚫 No transactions to scrape - most recent data is stale`);
              return [];
            } else {
              console.log(`✅ Most recent transaction date (${mostRecentISO}) is current or newer than target date (${targetISO})`);
            }
          } catch (parseError) {
            console.warn(`⚠️  Could not parse most recent date: "${mostRecentDateText}"`, parseError);
            // Continue with scraping if we can't parse the date
          }
        } else {
          console.warn(`⚠️  Could not extract most recent date from first day container`);
          // Continue with scraping if we can't extract the date
        }
      } catch (error) {
        console.warn(`⚠️  Error validating most recent date:`, error);
        // Continue with scraping if validation fails
      }
    }
    
    // Process only the specified number of recent days
    const daysToProcess = Math.min(daysToScrape, dayContainers.length);
    console.log(`📅 Processing ${daysToProcess} day(s) (requested: ${daysToScrape}, available: ${dayContainers.length})`);
    
    for (let i = 0; i < daysToProcess; i++) {
      // Check page validity before processing each day container
      if (!isPageValid()) {
        throw new Error(`Page became invalid while processing day container ${i + 1}`);
      }
      
      const dayContainer = dayContainers[i];
      console.log(`\n🗓️  Processing day container ${i + 1}/${daysToProcess}`);
      
      try {
        // Verify the day container is still attached to the DOM
        try {
          await dayContainer.evaluate((el: Element) => el.tagName); // This will throw if detached
        } catch (detachedError) {
          console.warn(`Day container ${i + 1} is detached, skipping:`, detachedError);
          continue;
        }
        // Extract the date from the day container
        // Look for date in header element first using robust selectors
        const headerElement = await dayContainer.$('[data-testid*="header"], [class*="header"], [class*="Header"], h1, h2, h3, h4, h5, h6');
        let dateText = '';
        
        if (headerElement) {
          dateText = await headerElement.evaluate((el: Element) => el.textContent?.trim() || '');
          console.log(`✅ Found date in header element: "${dateText}"`);
        } else {
          console.log(`⚠️  No header element found, trying fallback methods...`);
          // Fallback: look for any text that looks like a date in the container
          const allText = await dayContainer.evaluate((el: Element) => el.textContent || '');
          console.log(`🔍 Container text (first 200 chars): "${allText.substring(0, 200)}..."`);
          
          // First try to match properly formatted dates with comma and space
          const properDateMatch = allText.match(/\b(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),?\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}\b/i);
          if (properDateMatch) {
            dateText = properDateMatch[0];
            console.log(`✅ Proper date pattern matched: "${dateText}"`);
          } else {
            // Try to match dates without proper comma/space formatting
            const malformedDateMatch = allText.match(/\b(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),?\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2}\d{4}\b/i);
            if (malformedDateMatch) {
              // Fix the malformed date by adding comma and space
              dateText = malformedDateMatch[0].replace(/(\d{1,2})(\d{4})/, '$1, $2');
              console.log(`✅ Malformed date pattern matched and fixed: "${malformedDateMatch[0]}" -> "${dateText}"`);
            } else {
              // Try simpler date pattern (month day year)
              const simpleDateMatch = allText.match(/\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}\b/i);
              if (simpleDateMatch) {
                dateText = simpleDateMatch[0];
                console.log(`✅ Simple proper date pattern matched: "${dateText}"`);
              } else {
                // Try simple malformed pattern
                const simpleMalformedMatch = allText.match(/\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2}\d{4}\b/i);
                if (simpleMalformedMatch) {
                  dateText = simpleMalformedMatch[0].replace(/(\d{1,2})(\d{4})/, '$1, $2');
                  console.log(`✅ Simple malformed date pattern matched and fixed: "${simpleMalformedMatch[0]}" -> "${dateText}"`);
                } else {
                  console.log(`❌ All date patterns failed, using current date as fallback`);
                  // Use current date as fallback
                  dateText = new Date().toLocaleDateString();
                }
              }
            }
          }
        }
        
        // Find all transaction descriptions within this day using robust selectors
        const descriptionElements = await dayContainer.$$('[data-testid*="transaction"], [data-testid*="desc"], [class*="transaction"], [class*="Transaction"], [class*="desc"], [class*="Desc"], p, div');
        console.log(`📝 Found ${descriptionElements.length} potential transaction elements for this date`);
        
        let transactionsAddedForThisDay = 0;
        for (let index = 0; index < descriptionElements.length; index++) {
          // Check page validity before processing each transaction element
          if (!isPageValid()) {
            throw new Error(`Page became invalid while processing transaction ${index + 1} in day container ${i + 1}`);
          }
          
          const descElement = descriptionElements[index];
          
          // Verify the description element is still attached
          try {
            await descElement.evaluate((el: Element) => el.tagName); // This will throw if detached
          } catch (detachedError) {
            console.warn(`Transaction element ${index + 1} is detached, skipping:`, detachedError);
            continue;
          }
          
          const description = await descElement.evaluate((el: Element) => el.textContent?.trim() || '');
          
          // Filter out empty descriptions and non-transaction content
          if (description && description.length > 10 && 
              (description.toLowerCase().includes('signed') || 
               description.toLowerCase().includes('traded') || 
               description.toLowerCase().includes('waived') || 
               description.toLowerCase().includes('released') || 
               description.toLowerCase().includes('acquired') || 
               description.toLowerCase().includes('traded') || 
               description.toLowerCase().includes('contract') ||
               description.toLowerCase().includes('free agent') ||
               description.toLowerCase().includes('draft') ||
               description.toLowerCase().includes('assignment') ||
               description.toLowerCase().includes('recalled') ||
               description.toLowerCase().includes('option') ||
               description.toLowerCase().includes('exercise') ||
               description.toLowerCase().includes('decline') ||
               description.toLowerCase().includes('extension') ||
               description.toLowerCase().includes('restricted') ||
               description.toLowerCase().includes('unrestricted') ||
               description.toLowerCase().includes('player'))) {
            
            allTransactions.push({
              date: dateText,
              description: description
            });
            transactionsAddedForThisDay++;
            console.log(`  📋 Transaction ${index + 1}: "${description.substring(0, 80)}${description.length > 80 ? '...' : ''}"`);
          }
        }
        
        console.log(`✅ Added ${transactionsAddedForThisDay} transactions for date: "${dateText}"`);
        
      } catch (error) {
        console.warn(`❌ Error processing day container ${i + 1}:`, error);
      }
    }
    
    console.log(`\n🎯 Total transactions extracted: ${allTransactions.length}`);
    console.log(`📊 Summary by date:`);
    const dateSummary = allTransactions.reduce((acc, transaction) => {
      acc[transaction.date] = (acc[transaction.date] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);
    
    Object.entries(dateSummary).forEach(([date, count]) => {
      console.log(`  📅 "${date}": ${count} transactions`);
    });
    
    console.log(`Extracted ${allTransactions.length} raw transactions from ${daysToScrape} day(s)`);
    
    // Filter by target date in Node.js context (where regex works properly)
    if (targetDate) {
      const filteredTransactions = allTransactions.filter((transaction: any) => {
        // Use the same date cleaning logic as formatDateToISO
        let cleanedDate = transaction.date;
        
        // Fix concatenated date format before parsing
        cleanedDate = cleanedDate.replace(/(\d{1,2})(\d{4})/, '$1, $2');
        
        // Additional cleaning for edge cases
        // Handle "October20" -> "October 20" (month name + day concatenated)
        cleanedDate = cleanedDate.replace(/(January|February|March|April|May|June|July|August|September|October|November|December)(\d{1,2})/, '$1 $2');
        
        // Handle "Monday, October202025" -> "Monday, October 20, 2025" (comma + month + day + year)
        cleanedDate = cleanedDate.replace(/, (January|February|March|April|May|June|July|August|September|October|November|December)(\d{1,2})(\d{4})/, ', $1 $2, $3');
        
        // Handle "October202025" -> "October 20, 2025" (month name directly concatenated with day and year)
        cleanedDate = cleanedDate.replace(/(January|February|March|April|May|June|July|August|September|October|November|December)(\d{1,2})(\d{4})/, '$1 $2, $3');
        
        // Handle "Monday,October 20,2025" -> "Monday, October 20, 2025"
        cleanedDate = cleanedDate.replace(/,([A-Za-z])/, ', $1');
        
        // Handle "October 20,2025" -> "October 20, 2025" (missing space before year)
        cleanedDate = cleanedDate.replace(/,(\d{4})/, ', $1');
        
        try {
          const transactionDate = new Date(cleanedDate);
          
          // Use ISO date comparison to avoid timezone issues
          const transactionISO = transactionDate.toISOString().split('T')[0];
          const matches = transactionISO === targetDate;
          
          if (matches) {
            console.log(`✅ Matched transaction date: "${transaction.date}" (cleaned: "${cleanedDate}", ISO: ${transactionISO}) for target ${targetDate}`);
          }
          
          return matches;
        } catch (error) {
          console.warn(`❌ Failed to parse date: "${transaction.date}" (cleaned: "${cleanedDate}")`, error);
          return false;
        }
      });
      
      console.log(`Filtered to ${filteredTransactions.length} transactions for target date ${targetDate}`);
      return filteredTransactions;
    }
    
    return allTransactions;
    
  } catch (error) {
    console.error('Error scraping transactions from page:', error);
    throw error;
  }
}

/**
 * Select the best player name from a list of extracted names
 * Prioritizes clean, properly formatted names over partial extractions
 */
function selectBestPlayerName(playerNames: string[]): string {
  if (playerNames.length === 0) return '';
  if (playerNames.length === 1) return playerNames[0];
  
  // Score each player name based on quality indicators
  const scoredNames = playerNames.map(name => {
    let score = 0;
    const lowerName = name.toLowerCase();
    
    // Positive scoring (higher is better)
    if (/^[A-Z][a-z]+\s+[A-Z][a-z]+/.test(name)) score += 10; // Proper name format (First Last)
    if (/Jr\.?$|Sr\.?$|III$|IV$/.test(name)) score += 5; // Has suffix
    if (name.length >= 5 && name.length <= 25) score += 3; // Reasonable length
    if (/^[A-Z]/.test(name)) score += 2; // Starts with capital
    
    // Negative scoring (lower is worse)
    if (lowerName.includes('contract')) score -= 20; // Contains "contract"
    if (lowerName.includes('guard')) score -= 15; // Contains position
    if (lowerName.includes('forward')) score -= 15; // Contains position
    if (lowerName.includes('center')) score -= 15; // Contains position
    if (lowerName.includes('the ')) score -= 10; // Contains "the"
    if (lowerName.includes(' of ')) score -= 10; // Contains "of"
    if (name.length > 30) score -= 5; // Too long
    if (name.length < 3) score -= 5; // Too short
    
    return { name, score };
  });
  
  // Sort by score (highest first) and return the best name
  scoredNames.sort((a, b) => b.score - a.score);
  return scoredNames[0].name;
}

/**
 * Convert date string to YYYY-MM-DD format
 */
function formatDateToISO(dateString: string): string {
  try {
    console.log(`🔄 Formatting date: "${dateString}"`);
    
    // Handle various date formats from NBA.com
    // Examples: "Thursday, October 16, 2025", "Thursday, October 162025", "10/16/2025"
    
    // First, fix the common issue where day and year are concatenated
    // Handle "October 162025" -> "October 16, 2025"
    let cleanedDate = dateString.replace(/(\d{1,2})(\d{4})/, '$1, $2');
    
    // Additional cleaning for edge cases
    // Handle "October20" -> "October 20" (month name + day concatenated)
    cleanedDate = cleanedDate.replace(/(January|February|March|April|May|June|July|August|September|October|November|December)(\d{1,2})/, '$1 $2');
    
    // Handle "Monday, October202025" -> "Monday, October 20, 2025" (comma + month + day + year)
    cleanedDate = cleanedDate.replace(/, (January|February|March|April|May|June|July|August|September|October|November|December)(\d{1,2})(\d{4})/, ', $1 $2, $3');
    
    // Handle "October202025" -> "October 20, 2025" (month name directly concatenated with day and year)
    cleanedDate = cleanedDate.replace(/(January|February|March|April|May|June|July|August|September|October|November|December)(\d{1,2})(\d{4})/, '$1 $2, $3');
    
    // Handle "Monday,October 20,2025" -> "Monday, October 20, 2025"
    cleanedDate = cleanedDate.replace(/,([A-Za-z])/, ', $1');
    
    // Handle "October 20,2025" -> "October 20, 2025" (missing space before year)
    cleanedDate = cleanedDate.replace(/,(\d{4})/, ', $1');
    
    console.log(`🧹 Cleaned date: "${cleanedDate}"`);
    
    // Try to parse the date
    const parsedDate = new Date(cleanedDate);
    
    // Check if the date is valid
    if (isNaN(parsedDate.getTime())) {
      console.warn(`❌ Invalid date format: "${dateString}" -> "${cleanedDate}", using current date`);
      return new Date().toISOString().split('T')[0];
    }
    
    // Format as YYYY-MM-DD
    const year = parsedDate.getFullYear();
    const month = String(parsedDate.getMonth() + 1).padStart(2, '0');
    const day = String(parsedDate.getDate()).padStart(2, '0');
    
    const isoDate = `${year}-${month}-${day}`;
    console.log(`✅ Successfully formatted: "${dateString}" -> "${isoDate}"`);
    
    return isoDate;
    
  } catch (error) {
    console.warn(`❌ Error formatting date: "${dateString}"`, error);
    return new Date().toISOString().split('T')[0];
  }
}

/**
 * Process raw transaction data into structured NBA transactions with deduplication
 */
function processRawTransactions(rawTransactions: RawTransactionData[]): NBATransaction[] {
  const processedTransactions: NBATransaction[] = [];
  const seenTransactions = new Set<string>();
  
  for (const raw of rawTransactions) {
    try {
      // Skip transactions involving draft consideration or cash consideration
      const lowerDescription = raw.description.toLowerCase();
      if (lowerDescription.includes('draft consideration') || 
          lowerDescription.includes('cash consideration') ||
          lowerDescription.includes('cash considerations')) {
        console.log(`Skipping consideration transaction: ${raw.description.substring(0, 50)}...`);
        continue;
      }
      
      // Format date to YYYY-MM-DD
      const formattedDate = formatDateToISO(raw.date);
      
      // Parse player names from description
      const parsedNames = parsePlayerNamesFromDescription(raw.description);
      
      // Determine transaction type first
      const transactionType = parseTransactionType(raw.description);
      
      // Parse teams from description (now with transaction type context)
      const teams = parseTeamsFromDescription(raw.description, transactionType);
      
      // Single transaction item: choose the best parsed name (can be empty if none)
      const bestPlayerName = selectBestPlayerName(parsedNames);
      const normalizedDescription = raw.description.trim().toLowerCase();
      const uniqueKey = `${formattedDate}|${transactionType.toLowerCase()}|${normalizedDescription}`;
      if (!seenTransactions.has(uniqueKey)) {
        seenTransactions.add(uniqueKey);
        processedTransactions.push({
          date: formattedDate,
          playerName: bestPlayerName,
          transactionType: transactionType,
          fromTeam: teams.fromTeam,
          toTeam: teams.toTeam,
          description: raw.description
        });
      }
      
    } catch (error) {
      console.warn('Error processing transaction:', raw.description, error);
    }
  }
  
  console.log(`Processed ${processedTransactions.length} structured transactions (after deduplication)`);
  return processedTransactions;
}

/**
 * Scrape NBA transactions from the NBA.com transactions page with retry logic
 */
export async function scrapeNBATransactions(config: Partial<TransactionScraperConfig> = {}): Promise<NBATransaction[]> {
  const finalConfig = { ...DEFAULT_CONFIG, ...config };
  const maxRetries = 3;
  
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      console.log(`🔄 NBA transaction scraping attempt ${attempt}/${maxRetries}`);
      
      return await withPuppeteerBrowser(async (browser) => {
        const page = await createConfiguredPage(browser, {
          userAgent: finalConfig.userAgent,
          viewport: { width: 1920, height: 1080 }
        });
        
        // Navigate to NBA transactions page with enhanced error handling
        console.log(`Navigating to ${NBA_TRANSACTIONS_URL}...`);
        
        try {
          await page.goto(NBA_TRANSACTIONS_URL, { 
            waitUntil: 'networkidle2', // Use same robust wait condition as player scraper
            timeout: PAGE_LOAD_TIMEOUT 
          });
          
          // Wait for page to stabilize
          await setTimeout(3000);
          
          // Additional wait for dynamic content
          await page.waitForLoadState?.('networkidle') || await setTimeout(2000);
          
        } catch (navigationError) {
          console.error('Navigation failed, retrying with different strategy:', navigationError);
          
          // Retry with more conservative approach
          await page.goto(NBA_TRANSACTIONS_URL, { 
            waitUntil: 'networkidle2', // Use same robust wait condition as player scraper
            timeout: PAGE_LOAD_TIMEOUT 
          });
          
          await setTimeout(5000); // Longer wait for retry
        }
        
        // Scrape transactions
        const rawTransactions = await scrapeTransactionsFromPage(page, finalConfig.daysToScrape || 1, finalConfig.targetDate);
        
        // Process raw transactions into structured data
        const processedTransactions = processRawTransactions(rawTransactions);
        
        console.log(`NBA transaction scraping completed. Total transactions found: ${processedTransactions.length}`);
        return processedTransactions;
      }, { 
        scraperName: 'NBA transactions',
        skipIpCheck: true // Skip IP check for NBA scraper to be faster
      });
      
    } catch (error) {
      console.error(`❌ Attempt ${attempt} failed:`, error);
      
      if (attempt === maxRetries) {
        console.error(`💥 All ${maxRetries} attempts failed, throwing error`);
        throw error;
      }
      
      // Exponential backoff before retry
      const backoffDelay = Math.pow(2, attempt) * 1000; // 2s, 4s, 8s...
      console.log(`⏳ Waiting ${backoffDelay}ms before retry...`);
      await setTimeout(backoffDelay);
    }
  }
  
  throw new Error('Unexpected end of retry loop');
}

/**
 * Get NBA transactions with error handling and retries
 */
export async function fetchNBATransactionsWithRetry(
  daysToScrape: number = 1, 
  maxRetries: number = 3
): Promise<NBATransaction[]> {
  let lastError: Error | undefined;
  
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      console.log(`NBA transaction fetch attempt ${attempt}/${maxRetries}`);
      return await scrapeNBATransactions({ daysToScrape });
    } catch (error) {
      lastError = error as Error;
      console.error(`Attempt ${attempt} failed:`, error);
      
      if (attempt < maxRetries) {
        const delay = attempt * 5000; // Increasing delay: 5s, 10s, 15s
        console.log(`Retrying in ${delay}ms...`);
        await setTimeout(delay);
      }
    }
  }
  
  throw new Error(`NBA transaction scraping failed after ${maxRetries} attempts. Last error: ${lastError?.message}`);
}
