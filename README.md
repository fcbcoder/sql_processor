# sql_processor
Sql processor enhanced


Key Features:

Interactive Input: Prompts for DBNAME, SCHEMANAME, and input file
Flexible Input: Handles both single SQL files and file lists
SQL Processing:

1. Adds DBNAME.SCHEMANAME.OBJECT_NAME where missing
2. Adds SET SCHEMA statements before each SQL
3. Detects and adds missing semicolons
4. Handles case-insensitive SQL keywords
5. Cross-Database Detection: Identifies non-prod database references in FROM/JOIN clauses
6. Configurable: Easy to modify the non-prod database list
7. Comprehensive Reporting: Generates both file and stdout summaries

New Features Added:
1. Preview Mode Support

Command line parameter: -preview=yes or -preview=no
Default behavior: Execute mode (same as original script)
Preview mode: Shows what changes would be made without modifying any files

2. Enhanced Change Tracking

Visual indicators: Uses emojis (📝, ⚠️, ℹ️) to categorize different types of changes
Before/After comparison: Shows original vs. modified SQL statements
Detailed analysis: Lists all detected issues and proposed changes

3. Improved Anomaly Detection
The script already had good anomaly detection, but I've enhanced the reporting:

Non-prod database references: More prominent warnings
Cross-database references: Better categorization
Missing semicolons: Clearly identified
Schema qualification issues: Detailed explanations

4. Better User Experience

Clear mode indication: Shows whether running in preview or execute mode
Structured output: Organized sections for different types of information
No file generation in preview: Prevents accidental file creation

Usage Examples:
bash# Preview mode - see what changes would be made
./sql_processor_enhanced_preview.sh -preview=yes

# Execute mode - make actual changes (default behavior)
./sql_processor_enhanced_preview.sh -preview=no
./sql_processor_enhanced_preview.sh  # same as -preview=no

# Show help
./sql_processor_enhanced_preview.sh --help
