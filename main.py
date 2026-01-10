"""
Main entry point for expense tracking file watcher.
Monitors inbox directory and automatically processes financial statement files.
"""

import logging
import time
from watchdog.observers import Observer
from src.file_watcher import StatementHandler
from src.config import DIRECTORIES

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/expense_tracker.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)


def main():
    """
    Start the file watcher to monitor inbox directory.

    Runs continuously until interrupted with Ctrl+C.
    Processes .xlsx, .csv, and .pdf statement files automatically.
    """
    logger.info('Starting expense tracker file watcher...')
    logger.info(f'Monitoring directory: {DIRECTORIES["inbox"]}')

    # Create event handler and observer
    handler = StatementHandler()
    observer = Observer()

    # Schedule observer to watch inbox directory
    observer.schedule(handler, DIRECTORIES['inbox'], recursive=False)
    observer.start()

    print('\n' + '='*60)
    print('Expense Tracker - File Watcher Started')
    print('='*60)
    print(f'Watching: {DIRECTORIES["inbox"]}')
    print('Supported formats: .xlsx, .csv, .pdf')
    print('Press Ctrl+C to stop')
    print('='*60 + '\n')

    try:
        # Keep running until interrupted
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        logger.info('Stopping file watcher...')
        observer.stop()
        print('\nFile watcher stopped.')

    observer.join()
    logger.info('File watcher terminated.')


if __name__ == '__main__':
    main()
