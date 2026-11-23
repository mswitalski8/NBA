import {
  bulkInsertNBATeamHistory
} from '../../database';
import { sendCronSuccessNotification } from '../../notifications';
import { NBACronEvent, NBAPlayerRecord, NBATeamHistoryRecord, NBATransaction } from '../../types';
import {
  extractDateParameters,
  initializeCronHandler
} from '../cron-utils';
import { withCronErrorHandling } from '../error-handler';
import { runLocalHandler } from '../local-dev-utils';
import { getTransactionScrapingDate, logDateInfo } from './dateUtils';
import { scrapeNBAPlayers } from './playerScraper';
import { scrapeNBATransactions } from './transactionScraper';

const REQUEST_DELAY = 4000; // 4 seconds between scraper operations

// Processing result interface
interface ProcessingResult {
  records: NBATeamHistoryRecord[];
  errors: number;
  errorDetails: Array<{
    transactionId: string;
    error: string;
    playerName?: string;
  }>;
}

/**
 * Create or update NBA player lookup table
 */
async function updateNBAPlayerLookup(): Promise<Map<string, NBAPlayerRecord>> {
  console.log('Updating NBA player lookup table...');
  
  // Retry logic for frame detachment issues
  let players: NBAPlayerRecord[] = [];
  let retryCount = 0;
  const maxRetries = 3;
  
  while (retryCount < maxRetries) {
    try {
      console.log(`Attempt ${retryCount + 1}/${maxRetries} to scrape NBA players...`);
      
      // Detect if we're running locally vs in Lambda
      players = await scrapeNBAPlayers({
        headless: !!process.env.AWS_LAMBDA_FUNCTION_NAME, // If running in Lambda, use headless mode, else local run and use headed
        timeout: 120000 // 2 minutes for full scrape
      });
      
      console.log(`Successfully scraped ${players.length} NBA players on attempt ${retryCount + 1}`);
      break; // Success, exit retry loop
      
    } catch (error) {
      retryCount++;
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      if (errorMessage.includes('frame was detached') || errorMessage.includes('detached Frame') || errorMessage.includes('Target closed') || errorMessage.includes('Protocol error') || errorMessage.includes('Attempted to use detached') || errorMessage.includes('Connection closed')) {
        console.warn(`Frame detachment error on attempt ${retryCount}: ${errorMessage}`);
        
        if (retryCount < maxRetries) {
          console.log(`Retrying in ${retryCount * 2} seconds...`);
          await new Promise(resolve => setTimeout(resolve, retryCount * 2000));
          continue;
        } else {
          console.error(`Failed to scrape NBA players after ${maxRetries} attempts due to frame detachment`);
          throw new Error(`NBA player scraping failed after ${maxRetries} attempts: ${errorMessage}`);
        }
      } else {
        // Non-frame detachment error, don't retry
        console.error(`Non-retryable error during NBA player scraping: ${errorMessage}`);
        throw error;
      }
    }
  }
  
  console.log(`Scraped ${players.length} NBA players`);
  
  // Create lookup map by player name (case-insensitive)
  const playerLookup = new Map<string, NBAPlayerRecord>();
  
  players.forEach(player => {
    // Create multiple lookup keys for better matching
    const keys = [
      player.Name.toLowerCase(),
      player.Name.toLowerCase().replace(/\./g, ''), // Remove periods
      player.Name.toLowerCase().replace(/\s+/g, ''), // Remove spaces
      player.Name.toLowerCase().replace(/[^a-z\s]/g, ''), // Remove special chars
    ];
    
    keys.forEach(key => {
      if (key.length > 2) { // Only store meaningful keys
        playerLookup.set(key, player);
      }
    });
  });
  
  console.log(`Created lookup table with ${playerLookup.size} entries for ${players.length} players`);
  return playerLookup;
}

/**
 * Match transaction player name to NBA player ID
 */
function matchPlayerToId(playerName: string, playerLookup: Map<string, NBAPlayerRecord>): NBAPlayerRecord | null {
  if (!playerName || playerName.length < 2) {
    return null;
  }
  
  // Try different matching strategies
  const searchKeys = [
    playerName.toLowerCase(),
    playerName.toLowerCase().replace(/\./g, ''),
    playerName.toLowerCase().replace(/\s+/g, ''),
    playerName.toLowerCase().replace(/[^a-z\s]/g, ''),
    // Try partial matches for compound names
    playerName.toLowerCase().split(' ').join(''),
    playerName.toLowerCase().split(' ')[0], // First name only
    playerName.toLowerCase().split(' ').slice(-1)[0], // Last name only
  ];
  
  for (const key of searchKeys) {
    const match = playerLookup.get(key);
    if (match) {
      return match;
    }
  }
  
  // Try fuzzy matching (contains)
  for (const [lookupKey, player] of playerLookup.entries()) {
    if (lookupKey.includes(playerName.toLowerCase()) || 
        playerName.toLowerCase().includes(lookupKey)) {
      return player;
    }
  }
  
  return null;
}

/**
 * Convert team name to abbreviation
 */
function convertTeamToAbbreviation(teamName: string): string {
  const teamMap: Record<string, string> = {
    'Atlanta Hawks': 'ATL',
    'Boston Celtics': 'BOS',
    'Brooklyn Nets': 'BKN',
    'Charlotte Hornets': 'CHA',
    'Chicago Bulls': 'CHI',
    'Cleveland Cavaliers': 'CLE',
    'Dallas Mavericks': 'DAL',
    'Denver Nuggets': 'DEN',
    'Detroit Pistons': 'DET',
    'Golden State Warriors': 'GSW',
    'Houston Rockets': 'HOU',
    'Indiana Pacers': 'IND',
    'LA Clippers': 'LAC',
    'Los Angeles Lakers': 'LAL',
    'Memphis Grizzlies': 'MEM',
    'Miami Heat': 'MIA',
    'Milwaukee Bucks': 'MIL',
    'Minnesota Timberwolves': 'MIN',
    'New Orleans Pelicans': 'NOP',
    'New York Knicks': 'NYK',
    'Oklahoma City Thunder': 'OKC',
    'Orlando Magic': 'ORL',
    'Philadelphia 76ers': 'PHI',
    'Phoenix Suns': 'PHX',
    'Portland Trail Blazers': 'POR',
    'Sacramento Kings': 'SAC',
    'San Antonio Spurs': 'SAS',
    'Toronto Raptors': 'TOR',
    'Utah Jazz': 'UTA',
    'Washington Wizards': 'WAS'
  };
  
  return teamMap[teamName] || teamName;
}

/**
 * Process NBA transactions and match to player IDs
 */
function processNBATransactions(
  transactions: NBATransaction[],
  playerLookup: Map<string, NBAPlayerRecord>,
  validTeams: Set<string>
): ProcessingResult {
  const teamHistoryRecords: NBATeamHistoryRecord[] = [];
  const errorDetails: ProcessingResult['errorDetails'] = [];
  let errors = 0;

  console.log(`Processing ${transactions.length} NBA transactions...`);

  for (const transaction of transactions) {
    try {
      // Skip transactions without player names
      if (!transaction.playerName || transaction.playerName === 'Not specified') {
        errors++;
        errorDetails.push({
          transactionId: `${transaction.date}-${transaction.description.substring(0, 20)}`,
          error: 'Transaction missing player name',
          playerName: transaction.playerName
        });
        continue;
      }
      
      // Match player name to ID
      const playerMatch = matchPlayerToId(transaction.playerName, playerLookup);
      if (!playerMatch) {
        errors++;
        errorDetails.push({
          transactionId: `${transaction.date}-${transaction.playerName}`,
          error: 'Player not found in lookup table',
          playerName: transaction.playerName
        });
        continue;
      }
      
      // Use full team name (transaction.toTeam is already full team name, e.g., "Miami Heat")
      const toTeamFullName = transaction.toTeam;
      if (!toTeamFullName) {
        errors++;
        errorDetails.push({
          transactionId: `${transaction.date}-${transaction.playerName}`,
          error: 'No toTeam information found',
          playerName: transaction.playerName
        });
        continue;
      }
      
      // Filter by valid teams if provided (using full team names)
      if (validTeams.size > 0 && !validTeams.has(toTeamFullName)) {
        // This is expected filtering, not an error
        continue;
      }
      
      // Truncate description if too long (like MLB handler)
      let description = transaction.description || '';
      if (description.length > 255) {
        description = description.substring(0, 255);
      }
      
      // Get name parts from player lookup table (already parsed during scraping)
      const firstName = playerMatch.FirstName || '';
      const lastName = playerMatch.LastName || '';
      const middleName = 'N/A'; // Set to N/A to accommodate database structure
      
      // Parse birthdate from player lookup (format: YYYY-MM-DD string or undefined)
      let birthdate: Date;
      if (playerMatch.BirthDate) {
        birthdate = new Date(playerMatch.BirthDate);
      } else {
        birthdate = new Date('1900-01-01'); // Default if not available
      }
      
      // Create team history record with desired field order
      teamHistoryRecords.push({
        NBAPlayer: playerMatch.NBAPlayer,
        Date: new Date(transaction.date), // Convert string date to Date object
        NBATeam: toTeamFullName, // Use full team name (e.g., "Miami Heat")
        Description: description,
        FirstName: firstName,
        LastName: lastName,
        MiddleName: middleName,
        Birthdate: birthdate
      });
      
    } catch (error) {
      errors++;
      errorDetails.push({
        transactionId: `${transaction.date}-${transaction.playerName || 'unknown'}`,
        error: `Processing error: ${(error as Error).message}`,
        playerName: transaction.playerName
      });
    }
  }
  
  console.log(`Processed ${teamHistoryRecords.length} valid team history records from ${transactions.length} transactions`);
  if (errors > 0) {
    console.log(`⚠️ Encountered ${errors} non-fatal errors during processing`);
  }
  
  return {
    records: teamHistoryRecords,
    errors,
    errorDetails
  };
}

export const handler = async (event: NBACronEvent) => {
  console.log('NBA Player Team History upload started:', event);
  
  // Initialize handler with shared utilities
  const config = await initializeCronHandler('upload-nba-player-team-history');
  
  // Extract date parameters (for future use - currently scraping latest day)
  const { startDate, endDate } = extractDateParameters(event, config.environment);
  
  return await withCronErrorHandling(config, async () => {
    console.log(`Processing NBA transactions for date range: ${startDate} to ${endDate}`);
    
    // Step 1: Update NBA player lookup table
    //console.log('Step 1: Updating NBA player lookup...');
    //const playerLookup = await updateNBAPlayerLookup();
    
    // Add delay between scraper operations
   // await new Promise(resolve => setTimeout(resolve, REQUEST_DELAY));
    
    // Step 2: Determine target date for transaction scraping (always yesterday)
    const targetDate = getTransactionScrapingDate();
    logDateInfo(targetDate);

    const playerLookup = new Map<string, NBAPlayerRecord>(); // minimal stub



    
    // Step 3: Fetch NBA transactions for target date (yesterday)
    console.log(`Step 3: Fetching NBA transactions for ${targetDate}...`);
    const transactions = await scrapeNBATransactions({
      headless: !!process.env.AWS_LAMBDA_FUNCTION_NAME, // If running in Lambda, use headless mode, else local run and use headed
      daysToScrape: 1, // Only look at yesterday's transactions (previous day)
      targetDate: targetDate // Specific date to scrape
    });
    
    if (transactions.length === 0) {
      console.log('No transactions found for the specified date range');
      
      // Send success notification even with no transactions
      await sendCronSuccessNotification({
        jobName: 'upload-nba-player-team-history',
        startTime: config.easternTimeString,
        environment: config.environment,
        errorMessages: [],
        additionalInfo: {
          'Date': `${targetDate}`,
          'Transactions found': 0,
          'Records processed': 0,
          'Records inserted': 0,
          'Records updated': 0,
          'Total DB operations': 0,
          'Processing errors': 0,
          'Players in lookup': playerLookup.size
        }
      });
      
      return {
        statusCode: 200,
        body: JSON.stringify({
          message: 'No transactions found for the specified date range',
          targetDate,
          transactionsFound: 0,
          recordsProcessed: 0,
          recordsInserted: 0,
          recordsUpdated: 0,
          totalDbOperations: 0,
          environment: config.environment
        })
      };
    }
    
    // Step 3: Get valid teams (placeholder - no filtering for now)
    const validTeams = new Set<string>();
    console.log('No team filtering applied (NBA team validation not yet implemented)');
    
    // Step 4: Process and filter transactions
    console.log('Step 3: Processing and matching transactions...');
    const processingResult = processNBATransactions(transactions, playerLookup, validTeams);
    const { records: teamHistoryRecords, errors: processingErrors } = processingResult;
    
    // Step 5: Insert records into database
    let insertStats = { inserted: 0, updated: 0, total: 0, newPlayersCreated: 0 };
    if (teamHistoryRecords.length > 0) {
      console.log('Step 4: Inserting team history records into database...');
      // TODO: Implement birthdate scraping for NBA players - currently using default 1900-01-01
      console.log('⚠️ TODO: NBA player birthdates not yet implemented - using default date');
      console.log(`📊 Preparing to insert ${teamHistoryRecords.length} NBA team history records`);
      insertStats = await bulkInsertNBATeamHistory(teamHistoryRecords);
    } else {
      console.log('No valid team history records to insert');
    }
    
    // Step 6: Send success notification
    const errorMessages = processingResult.errorDetails.map(detail => {
      const playerInfo = detail.playerName ? ` (${detail.playerName})` : '';
      return `Transaction ${detail.transactionId}${playerInfo}: ${detail.error}`;
    });
    
    await sendCronSuccessNotification({
      jobName: 'upload-nba-player-team-history',
      startTime: config.easternTimeString,
      environment: config.environment,
      errorMessages,
      additionalInfo: {
        'Date': `${targetDate}`,
        'Transactions found': transactions.length,
        'Records processed': teamHistoryRecords.length,
        'Records inserted': insertStats.inserted,
        'Records updated': insertStats.updated,
        'New players created': insertStats.newPlayersCreated,
        'Total DB operations': insertStats.total,
        'Players in lookup': playerLookup.size,
        'Processing errors': processingErrors
      }
    });
    
    console.log('NBA Player Team History upload completed successfully');
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'NBA Player Team History upload completed successfully',
        targetDate,
        transactionsFound: transactions.length,
        recordsProcessed: teamHistoryRecords.length,
        recordsInserted: insertStats.inserted,
        recordsUpdated: insertStats.updated,
        newPlayersCreated: insertStats.newPlayersCreated,
        totalDbOperations: insertStats.total,
        playersInLookup: playerLookup.size,
        environment: config.environment
      })
    };
  });
};

// Direct execution support
if (require.main === module) {
  runLocalHandler('uploadNBAPlayerTeamHistory', handler).catch(console.error);
}
