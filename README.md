# sql_processor
Sql processor enhanced




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
./sql_processor_enhanced_v2.sh -preview=yes

# Execute mode - make actual changes (default behavior)
./sql_processor_enhanced_v2.sh -preview=no
./sql_processor_enhanced_v2.sh  # same as -preview=no

# Show help
./sql_processor_enhanced_v2.sh --help
