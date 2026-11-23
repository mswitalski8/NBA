// Date utility functions for NBA transaction scraping

/**
 * Get the previous day's date in YYYY-MM-DD format
 * Used for daily cron jobs to scrape the previous day's transactions
 */
export function getPreviousDay(fromDate?: Date): string {
  const date = fromDate || new Date();
  const previousDay = new Date(date);
  previousDay.setDate(date.getDate() - 1);
  
  return previousDay.toISOString().split('T')[0];
}

/**
 * Get a specific date in YYYY-MM-DD format
 */
export function formatDateToYYYYMMDD(date: Date): string {
  return date.toISOString().split('T')[0];
}

/**
 * Parse a date string and return a Date object
 */
export function parseDate(dateString: string): Date {
  return new Date(dateString);
}

/**
 * Check if a date string is in YYYY-MM-DD format
 */
export function isValidDateFormat(dateString: string): boolean {
  const regex = /^\d{4}-\d{2}-\d{2}$/;
  if (!regex.test(dateString)) {
    return false;
  }
  
  const date = new Date(dateString);
  return date instanceof Date && !isNaN(date.getTime());
}

/**
 * Get date range for transaction scraping
 * For daily cron: returns previous day
 * For manual runs: can specify custom date
 */
export function getTransactionScrapingDate(customDate?: string): string {
  if (customDate) {
    if (!isValidDateFormat(customDate)) {
      throw new Error(`Invalid date format: ${customDate}. Expected YYYY-MM-DD`);
    }
    return customDate;
  }
  
  // Default: previous day for daily cron
  return getPreviousDay();
}

/**
 * Log date information for debugging
 */
export function logDateInfo(targetDate: string): void {
  console.log(`🗓️  Date Configuration:`);
  console.log(`   Current Date: ${formatDateToYYYYMMDD(new Date())}`);
  console.log(`   Target Date: ${targetDate}`);
  console.log(`   Previous Day: ${getPreviousDay()}`);
}

