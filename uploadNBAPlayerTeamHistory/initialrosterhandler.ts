/**
 * NBA Initial Roster Handler
 * 
 * One-time scraper that:
 * - Scrapes all active NBA players (NO transactions)
 * - Inserts them into the transaction table with "On Initial Roster" description
 * - Uses today's date for all records
 */
import {
  bulkInsertNBATeamHistory
} from '../../database';
import { sendCronSuccessNotification } from '../../notifications';
import { NBACronEvent, NBAPlayerRecord, NBATeamHistoryRecord } from '../../types';
import {
  extractDateParameters,
  initializeCronHandler
} from '../cron-utils';
import { withCronErrorHandling } from '../error-handler';
import { runLocalHandler } from '../local-dev-utils';
import { scrapeNBAPlayers } from './playerScraper';

console.log('📋 Loaded: initialrosterhandler.ts - One-time initial roster scraper (no transactions)');

const REQUEST_DELAY = 4000; // 4 seconds between scraper operations

/**
 * Convert active players to initial roster team history records
 */
function convertPlayersToInitialRoster(
  players: NBAPlayerRecord[]
): NBATeamHistoryRecord[] {
  const today = new Date();
  today.setHours(0, 0, 0, 0); // Set to start of day
  
  const teamHistoryRecords: NBATeamHistoryRecord[] = [];
  
  console.log(`Converting ${players.length} active players to initial roster records...`);
  
  for (const player of players) {
    try {
      // Get name parts from player record
      const firstName = player.FirstName || '';
      const lastName = player.LastName || '';
      const middleName = 'N/A'; // Set to N/A to accommodate database structure
      
      // Parse birthdate from player record (format: YYYY-MM-DD string or undefined)
      let birthdate: Date;
      if (player.BirthDate) {
        birthdate = new Date(player.BirthDate);
      } else {
        birthdate = new Date('1900-01-01'); // Default if not available
      }
      
      // Create team history record with desired field order
      teamHistoryRecords.push({
        NBAPlayer: player.NBAPlayer,
        Date: today, // Use today's date
        NBATeam: player.CurrentTeam, // Use full team name (e.g., "Miami Heat")
        Description: 'On Initial Roster',
        FirstName: firstName,
        LastName: lastName,
        MiddleName: middleName,
        Birthdate: birthdate
      });
      
    } catch (error) {
      console.warn(`Error processing player ${player.Name}:`, error);
      // Continue processing other players
    }
  }
  
  console.log(`Successfully converted ${teamHistoryRecords.length} players to initial roster records`);
  return teamHistoryRecords;
}

export const handler = async (event: NBACronEvent) => {
  console.log('🏀 NBA Initial Roster Handler - Starting one-time scrape of all active players');
  console.log('NBA Initial Roster upload started:', event);
  
  // Initialize handler with shared utilities
  const config = await initializeCronHandler('upload-nba-initial-roster');
  
  // Extract date parameters (not used for initial roster, but required by interface)
  const { startDate, endDate } = extractDateParameters(event, config.environment);
  
  return await withCronErrorHandling(config, async () => {
    console.log('Processing NBA initial roster (all active players)...');
    
    // Step 1: Scrape all active NBA players
    console.log('Step 1: Scraping all active NBA players...');
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
    
    if (players.length === 0) {
      console.log('No players found');
      
      // Send success notification even with no players
      await sendCronSuccessNotification({
        jobName: 'upload-nba-initial-roster',
        startTime: config.easternTimeString,
        environment: config.environment,
        errorMessages: [],
        additionalInfo: {
          'Date': new Date().toISOString().split('T')[0],
          'Players found': 0,
          'Records processed': 0,
          'Records inserted': 0,
          'Records updated': 0,
          'Total DB operations': 0
        }
      });
      
      return {
        statusCode: 200,
        body: JSON.stringify({
          message: 'No players found for initial roster',
          playersFound: 0,
          recordsProcessed: 0,
          recordsInserted: 0,
          recordsUpdated: 0,
          totalDbOperations: 0,
          environment: config.environment
        })
      };
    }
    
    // Step 2: Convert players to initial roster team history records
    console.log('Step 2: Converting players to initial roster records...');
    const teamHistoryRecords = convertPlayersToInitialRoster(players);
    
    // Step 3: Insert records into database
    let insertStats = { inserted: 0, updated: 0, total: 0, newPlayersCreated: 0 };
    if (teamHistoryRecords.length > 0) {
      console.log('Step 3: Inserting initial roster records into database...');
      console.log(`📊 Preparing to insert ${teamHistoryRecords.length} NBA initial roster records`);
      insertStats = await bulkInsertNBATeamHistory(teamHistoryRecords);
    } else {
      console.log('No valid initial roster records to insert');
    }
    
    // Step 4: Send success notification
    const today = new Date().toISOString().split('T')[0];
    await sendCronSuccessNotification({
      jobName: 'upload-nba-initial-roster',
      startTime: config.easternTimeString,
      environment: config.environment,
      errorMessages: [],
      additionalInfo: {
        'Date': today,
        'Players found': players.length,
        'Records processed': teamHistoryRecords.length,
        'Records inserted': insertStats.inserted,
        'Records updated': insertStats.updated,
        'New players created': insertStats.newPlayersCreated,
        'Total DB operations': insertStats.total
      }
    });
    
    console.log('NBA Initial Roster upload completed successfully');
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'NBA Initial Roster upload completed successfully',
        date: today,
        playersFound: players.length,
        recordsProcessed: teamHistoryRecords.length,
        recordsInserted: insertStats.inserted,
        recordsUpdated: insertStats.updated,
        newPlayersCreated: insertStats.newPlayersCreated,
        totalDbOperations: insertStats.total,
        environment: config.environment
      })
    };
  });
};

// Direct execution support
if (require.main === module) {
  runLocalHandler('uploadNBAInitialRoster', handler).catch(console.error);
}
