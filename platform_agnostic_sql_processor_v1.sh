#!/bin/sh

# SQL File Processor Script with Preview Mode - Platform Agnostic Version
# Processes SQL files to add database/schema qualifiers and generate reports
# Compatible with: Linux, AIX, Solaris, HP-UX, macOS, and other Unix variants

# Configuration - Non-prod database names (easily configurable)
NON_PROD_DBS="STGDV STGQA CIDDV CIDQA DEV TEST UAT"

# Global variables
DBNAME=""
SCHEMANAME=""
INPUT_FILE=""
OUTPUT_FILE=""
SUMMARY_FILE=""
SUMMARY_CONTENT=""
PREVIEW_MODE="false"
LINE_NUMBER=0
CURRENT_FILE=""
CURRENT_STATEMENT=""
STATEMENT_START_LINE=0
PREVIEW_CHANGES=""
TEMP_DIR=""

# Function to detect the platform and set appropriate commands
detect_platform() {
    # Detect operating system
    OS_TYPE=$(uname -s 2>/dev/null || echo "Unknown")
    
    # Set platform-specific commands
    case "$OS_TYPE" in
        AIX)
            # AIX-specific settings
            ECHO_CMD="echo"
            SED_CMD="sed"
            AWK_CMD="awk"
            DATE_CMD="date"
            TR_CMD="tr"
            ;;
        SunOS)
            # Solaris-specific settings
            ECHO_CMD="/usr/bin/echo"
            SED_CMD="/usr/bin/sed"
            AWK_CMD="/usr/bin/awk"
            DATE_CMD="/usr/bin/date"
            TR_CMD="/usr/bin/tr"
            ;;
        HP-UX)
            # HP-UX-specific settings
            ECHO_CMD="echo"
            SED_CMD="sed"
            AWK_CMD="awk"
            DATE_CMD="date"
            TR_CMD="tr"
            ;;
        Linux|Darwin)
            # Linux and macOS
            ECHO_CMD="echo"
            SED_CMD="sed"
            AWK_CMD="awk"
            DATE_CMD="date"
            TR_CMD="tr"
            ;;
        *)
            # Default for other Unix systems
            ECHO_CMD="echo"
            SED_CMD="sed"
            AWK_CMD="awk"
            DATE_CMD="date"
            TR_CMD="tr"
            ;;
    esac
    
    # Create a temporary directory that works across platforms
    if [ -d "/tmp" ]; then
        TEMP_DIR="/tmp/sql_processor_$$"
    elif [ -d "/var/tmp" ]; then
        TEMP_DIR="/var/tmp/sql_processor_$$"
    else
        TEMP_DIR="./sql_processor_$$"
    fi
    mkdir -p "$TEMP_DIR" 2>/dev/null
}

# Function to display usage
show_usage() {
    $ECHO_CMD "Usage: $0 [-preview=yes|no] [-h|--help]"
    $ECHO_CMD "This script processes SQL files to add database/schema qualifiers"
    $ECHO_CMD ""
    $ECHO_CMD "Options:"
    $ECHO_CMD "  -preview=yes    Show preview of changes without modifying files"
    $ECHO_CMD "  -preview=no     Make changes and generate output files (default)"
    $ECHO_CMD "  -h, --help      Show this help message"
    $ECHO_CMD ""
    $ECHO_CMD "You will be prompted for:"
    $ECHO_CMD "  - DBNAME: Target database name"
    $ECHO_CMD "  - SCHEMANAME: Target schema name" 
    $ECHO_CMD "  - Input: Single SQL file OR file containing list of SQL files"
    $ECHO_CMD ""
    $ECHO_CMD "Platform: $OS_TYPE"
}

# Function to parse command line arguments
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -preview=yes)
                PREVIEW_MODE="true"
                shift
                ;;
            -preview=no)
                PREVIEW_MODE="false"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                # Unknown option
                $ECHO_CMD "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to convert string to uppercase (portable)
to_upper() {
    $ECHO_CMD "$1" | $TR_CMD '[:lower:]' '[:upper:]'
}

# Function to convert string to lowercase (portable)
to_lower() {
    $ECHO_CMD "$1" | $TR_CMD '[:upper:]' '[:lower:]'
}

# Function to trim whitespace (portable)
trim() {
    $ECHO_CMD "$1" | $SED_CMD 's/^[ \t]*//;s/[ \t]*$//'
}

# Function to prompt for inputs (portable read)
get_inputs() {
    $ECHO_CMD "=== SQL File Processor ==="
    if [ "$PREVIEW_MODE" = "true" ]; then
        $ECHO_CMD "=== PREVIEW MODE - No files will be modified ==="
    fi
    $ECHO_CMD ""
    
    # Get database name
    while [ -z "$DBNAME" ]; do
        printf "Enter DBNAME (target database name): "
        read DBNAME
        DBNAME=$(trim "$DBNAME")
        if [ -z "$DBNAME" ]; then
            $ECHO_CMD "DBNAME cannot be empty. Please try again."
        fi
    done
    
    # Get schema name
    while [ -z "$SCHEMANAME" ]; do
        printf "Enter SCHEMANAME (target schema name): "
        read SCHEMANAME
        SCHEMANAME=$(trim "$SCHEMANAME")
        if [ -z "$SCHEMANAME" ]; then
            $ECHO_CMD "SCHEMANAME cannot be empty. Please try again."
        fi
    done
    
    # Get input file
    while [ -z "$INPUT_FILE" ]; do
        printf "Enter input file (single SQL file or file containing list of SQL files): "
        read INPUT_FILE
        INPUT_FILE=$(trim "$INPUT_FILE")
        if [ ! -f "$INPUT_FILE" ]; then
            $ECHO_CMD "File '$INPUT_FILE' not found. Please try again."
            INPUT_FILE=""
        fi
    done
    
    # Set output files (only if not in preview mode)
    if [ "$PREVIEW_MODE" = "false" ]; then
        TIMESTAMP=$($DATE_CMD "+%Y%m%d_%H%M%S" 2>/dev/null || $DATE_CMD | $SED_CMD 's/ /_/g')
        OUTPUT_FILE="combined_output_${TIMESTAMP}.sql"
        SUMMARY_FILE="processing_summary_${TIMESTAMP}.txt"
    else
        OUTPUT_FILE="[PREVIEW MODE - No output file will be created]"
        SUMMARY_FILE="[PREVIEW MODE - No summary file will be created]"
    fi
    
    $ECHO_CMD ""
    $ECHO_CMD "Configuration:"
    if [ "$PREVIEW_MODE" = "true" ]; then
        $ECHO_CMD "  Mode: PREVIEW"
    else
        $ECHO_CMD "  Mode: EXECUTE"
    fi
    $ECHO_CMD "  Platform: $OS_TYPE"
    $ECHO_CMD "  DBNAME: $DBNAME"
    $ECHO_CMD "  SCHEMANAME: $SCHEMANAME"
    $ECHO_CMD "  Input file: $INPUT_FILE"
    $ECHO_CMD "  Output file: $OUTPUT_FILE"
    $ECHO_CMD "  Summary file: $SUMMARY_FILE"
    $ECHO_CMD ""
}

# Function to check if a database name is non-prod (case-insensitive, portable)
is_non_prod_db() {
    db_name="$1"
    db_name_upper=$(to_upper "$db_name")
    
    # Convert NON_PROD_DBS to newline-separated format for processing
    $ECHO_CMD "$NON_PROD_DBS" | $TR_CMD ' ' '\n' | while read non_prod; do
        if [ -n "$non_prod" ]; then
            non_prod_upper=$(to_upper "$non_prod")
            if [ "$db_name_upper" = "$non_prod_upper" ]; then
                $ECHO_CMD "MATCH"
                return 0
            fi
        fi
    done | grep -q "MATCH"
}

# Function to add to summary
add_to_summary() {
    message="$1"
    if [ -z "$SUMMARY_CONTENT" ]; then
        SUMMARY_CONTENT="$message"
    else
        SUMMARY_CONTENT="$SUMMARY_CONTENT
$message"
    fi
}

# Function to add to preview changes
add_to_preview() {
    message="$1"
    if [ -z "$PREVIEW_CHANGES" ]; then
        PREVIEW_CHANGES="$message"
    else
        PREVIEW_CHANGES="$PREVIEW_CHANGES
$message"
    fi
}

# Function to extract database and schema from qualified name (portable)
extract_db_schema() {
    qualified_name="$1"
    db_part=""
    schema_part=""
    object_part=""
    
    # Remove any trailing parentheses, commas, or other characters
    qualified_name=$($ECHO_CMD "$qualified_name" | $SED_CMD 's/[(),;[:space:]]*$//')
    
    # Count dots to determine format
    dot_count=$($ECHO_CMD "$qualified_name" | $TR_CMD -cd '.' | wc -c)
    dot_count=$(trim "$dot_count")
    
    if [ "$dot_count" = "2" ]; then
        # Format: db.schema.object
        db_part=$($ECHO_CMD "$qualified_name" | $AWK_CMD -F'.' '{print $1}')
        schema_part=$($ECHO_CMD "$qualified_name" | $AWK_CMD -F'.' '{print $2}')
        object_part=$($ECHO_CMD "$qualified_name" | $AWK_CMD -F'.' '{print $3}')
    elif [ "$dot_count" = "1" ]; then
        # Format: schema.object
        schema_part=$($ECHO_CMD "$qualified_name" | $AWK_CMD -F'.' '{print $1}')
        object_part=$($ECHO_CMD "$qualified_name" | $AWK_CMD -F'.' '{print $2}')
    else
        # Format: object
        object_part="$qualified_name"
    fi
    
    $ECHO_CMD "$db_part|$schema_part|$object_part"
}

# Function to check if a statement is complete (ends with semicolon, portable)
is_statement_complete() {
    statement="$1"
    # Remove comments and whitespace, then check if it ends with semicolon
    cleaned_statement=$($ECHO_CMD "$statement" | $SED_CMD 's/--.*$//' | $SED_CMD 's/[[:space:]]*$//')
    # Check if it ends with semicolon
    case "$cleaned_statement" in
        *";") return 0 ;;
        *) return 1 ;;
    esac
}

# Function to identify SQL statement type and extract object name (portable)
identify_statement_type() {
    statement="$1"
    statement_upper=$(to_upper "$statement")
    
    # Remove comments and extra whitespace
    statement_upper=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/--.*$//' | $TR_CMD '\n' ' ' | $SED_CMD 's/[[:space:]]\+/ /g' | $SED_CMD 's/^[[:space:]]*//')
    
    stmt_type=""
    object_name=""
    
    # Use portable pattern matching instead of bash regex
    case "$statement_upper" in
        "CREATE TABLE "*)
            stmt_type="CREATE TABLE"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^CREATE TABLE[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
        "CREATE OR REPLACE VIEW "*)
            stmt_type="CREATE OR REPLACE VIEW"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^CREATE OR REPLACE VIEW[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
        "CREATE VIEW "*)
            stmt_type="CREATE VIEW"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^CREATE VIEW[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
        "CREATE UNIQUE INDEX "*)
            stmt_type="CREATE UNIQUE INDEX"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^CREATE UNIQUE INDEX[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
        "CREATE INDEX "*)
            stmt_type="CREATE INDEX"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^CREATE INDEX[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
        "CREATE PROCEDURE "*)
            stmt_type="CREATE PROCEDURE"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^CREATE PROCEDURE[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
        "CREATE FUNCTION "*)
            stmt_type="CREATE FUNCTION"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^CREATE FUNCTION[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
        "DROP TABLE "*)
            stmt_type="DROP TABLE"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^DROP TABLE[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
        "DROP VIEW "*)
            stmt_type="DROP VIEW"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^DROP VIEW[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
        "DROP INDEX "*)
            stmt_type="DROP INDEX"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^DROP INDEX[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
        "ALTER TABLE "*)
            stmt_type="ALTER TABLE"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^ALTER TABLE[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
        "INSERT INTO "*)
            stmt_type="INSERT INTO"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^INSERT INTO[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
        "UPDATE "*)
            stmt_type="UPDATE"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^UPDATE[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
        "DELETE FROM "*)
            stmt_type="DELETE FROM"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^DELETE FROM[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
        "TRUNCATE TABLE "*)
            stmt_type="TRUNCATE TABLE"
            object_name=$($ECHO_CMD "$statement_upper" | $SED_CMD 's/^TRUNCATE TABLE[[:space:]]\+//' | $AWK_CMD '{print $1}' | $SED_CMD 's/[(),[:space:]].*//')
            ;;
    esac
    
    $ECHO_CMD "$stmt_type|$object_name"
}

# Function to find cross-database references in FROM/JOIN clauses (portable)
find_cross_db_references() {
    statement="$1"
    statement_upper=$(to_upper "$statement")
    
    # Create temporary file for processing
    temp_file="$TEMP_DIR/refs_$$"
    
    # Extract FROM clauses
    $ECHO_CMD "$statement_upper" | $SED_CMD 's/FROM[[:space:]]\+\([^[:space:],()]\+\)/\nFROM_REF:\1\n/g' | grep "^FROM_REF:" | $SED_CMD 's/^FROM_REF://' > "$temp_file"
    
    # Extract JOIN clauses
    $ECHO_CMD "$statement_upper" | $SED_CMD 's/\(INNER[[:space:]]\+JOIN\|LEFT[[:space:]]\+OUTER[[:space:]]\+JOIN\|RIGHT[[:space:]]\+OUTER[[:space:]]\+JOIN\|FULL[[:space:]]\+OUTER[[:space:]]\+JOIN\|LEFT[[:space:]]\+JOIN\|RIGHT[[:space:]]\+JOIN\|FULL[[:space:]]\+JOIN\|CROSS[[:space:]]\+JOIN\|JOIN\)[[:space:]]\+\([^[:space:],()]\+\)/\nJOIN_REF:\2\n/g' | grep "^JOIN_REF:" | $SED_CMD 's/^JOIN_REF://' >> "$temp_file"
    
    # Check each reference for cross-database usage
    if [ -f "$temp_file" ]; then
        while read ref_obj; do
            if [ -n "$ref_obj" ]; then
                ref_db_schema_obj=$(extract_db_schema "$ref_obj")
                ref_db_part=$($ECHO_CMD "$ref_db_schema_obj" | $AWK_CMD -F'|' '{print $1}')
                
                if [ -n "$ref_db_part" ] && [ "$(to_upper "$ref_db_part")" != "$(to_upper "$DBNAME")" ]; then
                    if is_non_prod_db "$ref_db_part"; then
                        add_to_summary "WARNING: File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - NON-PROD database reference found: $ref_db_part in object $ref_obj"
                        if [ "$PREVIEW_MODE" = "true" ]; then
                            add_to_preview "⚠️  WARNING: Non-prod database reference '$ref_db_part' found in $ref_obj"
                        fi
                    else
                        add_to_summary "INFO: File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - Cross-database reference found: $ref_db_part in object $ref_obj"
                        if [ "$PREVIEW_MODE" = "true" ]; then
                            add_to_preview "ℹ️  INFO: Cross-database reference '$ref_db_part' found in $ref_obj"
                        fi
                    fi
                fi
            fi
        done < "$temp_file"
        rm -f "$temp_file"
    fi
}

# Function to process a complete SQL statement (portable)
process_sql_statement() {
    statement="$1"
    last_set_schema="$2"
    processed_statement="$statement"
    set_schema_line=""
    needs_semicolon="false"
    changes_made="false"
    
    # Skip empty statements
    cleaned_statement=$($ECHO_CMD "$statement" | $SED_CMD 's/--.*$//' | $SED_CMD 's/[[:space:]]*$//' | $TR_CMD -d '\n\r')
    if [ -z "$cleaned_statement" ]; then
        if [ "$PREVIEW_MODE" = "false" ]; then
            $ECHO_CMD "$statement"
        fi
        return
    fi
    
    # Check if this is a SET SCHEMA statement
    stmt_upper=$(to_upper "$statement")
    stmt_upper_trimmed=$(echo "$stmt_upper" | sed 's/^[[:space:]]*//')
    case "$stmt_upper_trimmed" in
        "SET SCHEMA "*)
            # Extract existing schema name
            existing_schema=$(echo "$stmt_upper_trimmed" | sed 's/^SET[[:space:]]\+SCHEMA[[:space:]]\+//' | awk '{print $1}' | sed 's/[;[:space:]]*$//')
            add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - Found existing SET SCHEMA $existing_schema"
            
            # Add semicolon if needed
            if ! is_statement_complete "$statement"; then
                processed_statement="$processed_statement;"
                add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - Added missing semicolon to SET SCHEMA"
                if [ "$PREVIEW_MODE" = "true" ]; then
                    add_to_preview "📝 Line $STATEMENT_START_LINE-$LINE_NUMBER: Would add missing semicolon to SET SCHEMA"
                fi
                changes_made="true"
            fi
            
            if [ "$PREVIEW_MODE" = "false" ]; then
                $ECHO_CMD "$processed_statement"
            elif [ "$changes_made" = "true" ]; then
                add_to_preview "   Before: $($ECHO_CMD "$statement" | $TR_CMD -d '\n')"
                add_to_preview "   After:  $($ECHO_CMD "$processed_statement" | $TR_CMD -d '\n')"
            fi
            return
            ;;
    esac
    
    # Check if statement ends with semicolon
    if ! is_statement_complete "$statement"; then
        needs_semicolon="true"
    fi
    
    # Identify statement type and object
    stmt_info=$(identify_statement_type "$statement")
    stmt_type=$($ECHO_CMD "$stmt_info" | $AWK_CMD -F'|' '{print $1}')
    object_name=$($ECHO_CMD "$stmt_info" | $AWK_CMD -F'|' '{print $2}')
    
    # Process DDL/DML statements
    if [ -n "$stmt_type" ] && [ -n "$object_name" ]; then
        # Parse the object name
        db_schema_obj=$(extract_db_schema "$object_name")
        db_part=$($ECHO_CMD "$db_schema_obj" | $AWK_CMD -F'|' '{print $1}')
        schema_part=$($ECHO_CMD "$db_schema_obj" | $AWK_CMD -F'|' '{print $2}')
        obj_part=$($ECHO_CMD "$db_schema_obj" | $AWK_CMD -F'|' '{print $3}')
        
        # Determine what to do based on current format
        if [ -n "$db_part" ] && [ -n "$schema_part" ]; then
            # Already has db.schema.object format
            add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - $stmt_type statement already has DBNAME ($db_part) - no modification needed"
            # Only add SET SCHEMA if it's different from the last one
            if [ "$(to_upper "$schema_part")" != "$(to_upper "$last_set_schema")" ]; then
                set_schema_line="SET SCHEMA $schema_part;"
                if [ "$PREVIEW_MODE" = "true" ]; then
                    add_to_preview "📝 Line $STATEMENT_START_LINE: Would add SET SCHEMA $schema_part;"
                fi
                changes_made="true"
            else
                add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - SET SCHEMA $schema_part already in effect, skipping"
            fi
        elif [ -n "$schema_part" ]; then
            # Has schema.object format - add database
            new_object_name="$DBNAME.$schema_part.$obj_part"
            # Use portable replacement
            processed_statement=$($ECHO_CMD "$processed_statement" | $SED_CMD "s/\\b$object_name\\b/$new_object_name/g")
            add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - Added DBNAME to $stmt_type: $object_name -> $new_object_name"
            if [ "$PREVIEW_MODE" = "true" ]; then
                add_to_preview "📝 Line $STATEMENT_START_LINE-$LINE_NUMBER: Would change $stmt_type object: $object_name -> $new_object_name"
            fi
            changes_made="true"
            # Only add SET SCHEMA if it's different from the last one
            if [ "$(to_upper "$schema_part")" != "$(to_upper "$last_set_schema")" ]; then
                set_schema_line="SET SCHEMA $schema_part;"
                if [ "$PREVIEW_MODE" = "true" ]; then
                    add_to_preview "📝 Line $STATEMENT_START_LINE: Would add SET SCHEMA $schema_part;"
                fi
            else
                add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - SET SCHEMA $schema_part already in effect, skipping"
            fi
        else
            # Has only object format - add database and schema
            new_object_name="$DBNAME.$SCHEMANAME.$obj_part"
            # Use portable replacement
            processed_statement=$($ECHO_CMD "$processed_statement" | $SED_CMD "s/\\b$object_name\\b/$new_object_name/g")
            add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - Added DBNAME.SCHEMANAME to $stmt_type: $object_name -> $new_object_name"
            if [ "$PREVIEW_MODE" = "true" ]; then
                add_to_preview "📝 Line $STATEMENT_START_LINE-$LINE_NUMBER: Would change $stmt_type object: $object_name -> $new_object_name"
            fi
            changes_made="true"
            # Only add SET SCHEMA if it's different from the last one
            if [ "$(to_upper "$SCHEMANAME")" != "$(to_upper "$last_set_schema")" ]; then
                set_schema_line="SET SCHEMA $SCHEMANAME;"
                if [ "$PREVIEW_MODE" = "true" ]; then
                    add_to_preview "📝 Line $STATEMENT_START_LINE: Would add SET SCHEMA $SCHEMANAME;"
                fi
            else
                add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - SET SCHEMA $SCHEMANAME already in effect, skipping"
            fi
        fi
        
        # Check for cross-database references
        find_cross_db_references "$statement"
    fi
    
    # Add semicolon if needed
    if [ "$needs_semicolon" = "true" ]; then
        processed_statement="$processed_statement;"
        add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - Added missing semicolon"
        if [ "$PREVIEW_MODE" = "true" ]; then
            add_to_preview "📝 Line $STATEMENT_START_LINE-$LINE_NUMBER: Would add missing semicolon"
        fi
        changes_made="true"
    fi
    
    # In preview mode, show before/after if changes were made
    if [ "$PREVIEW_MODE" = "true" ] && [ "$changes_made" = "true" ]; then
        add_to_preview "   Before: $($ECHO_CMD "$statement" | $TR_CMD -d '\n')"
        if [ -n "$set_schema_line" ]; then
            add_to_preview "   After:  $set_schema_line$($ECHO_CMD "$processed_statement" | $TR_CMD -d '\n')"
        else
            add_to_preview "   After:  $($ECHO_CMD "$processed_statement" | $TR_CMD -d '\n')"
        fi
        add_to_preview ""
    fi
    
    # Output in execute mode
    if [ "$PREVIEW_MODE" = "false" ]; then
        # Output SET SCHEMA line if needed
        if [ -n "$set_schema_line" ]; then
            $ECHO_CMD "$set_schema_line"
        fi
        
        # Output the processed statement
        $ECHO_CMD "$processed_statement"
    fi
}

# Function to process a single SQL file
process_sql_file() {
    file_path="$1"
    
    if [ ! -f "$file_path" ]; then
        add_to_summary "ERROR: File not found: $file_path"
        return 1
    fi
    
    CURRENT_FILE="$file_path"
    add_to_summary "Processing file: $file_path"
    
    if [ "$PREVIEW_MODE" = "true" ]; then
        add_to_preview "🔍 Analyzing file: $file_path"
        add_to_preview "======================================"
    else
        $ECHO_CMD "-- File: $file_path"
        $ECHO_CMD "-- Processed on: $($DATE_CMD)"
        $ECHO_CMD ""
    fi
    
    LINE_NUMBER=0
    CURRENT_STATEMENT=""
    STATEMENT_START_LINE=0
    in_statement="false"
    last_set_schema=""
    
    while IFS= read -r line || [ -n "$line" ]; do
        LINE_NUMBER=$((LINE_NUMBER + 1))
        
        # Remove carriage return characters (Windows line endings)
        line=$($ECHO_CMD "$line" | $TR_CMD -d '\r')
        
        # Skip pure comment lines and empty lines when not in a statement
        if [ "$in_statement" != "true" ]; then
            # Check for empty line
            if [ -z "$line" ]; then
                if [ "$PREVIEW_MODE" = "false" ]; then
                    $ECHO_CMD "$line"
                fi
                continue
            fi
            # Check for whitespace-only line
            trimmed_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -z "$trimmed_line" ]; then
                if [ "$PREVIEW_MODE" = "false" ]; then
                    $ECHO_CMD "$line"
                fi
                continue
            fi
            # Check for comment line
            case "$trimmed_line" in
                "--"*)
                    if [ "$PREVIEW_MODE" = "false" ]; then
                        $ECHO_CMD "$line"
                    fi
                    continue
                    ;;
            esac
        fi
        
        # Check if this line starts a new SQL statement
        line_upper=$(to_upper "$line")
        # Remove leading whitespace for pattern matching
        line_upper_trimmed=$(echo "$line_upper" | sed 's/^[[:space:]]*//')
        case "$line_upper_trimmed" in
            "CREATE "*|\
            "INSERT "*|\
            "UPDATE "*|\
            "DELETE "*|\
            "SELECT "*|\
            "WITH "*|\
            "SET "*|\
            "DROP "*|\
            "ALTER "*|\
            "GRANT "*|\
            "REVOKE "*|\
            "TRUNCATE "*)
                if [ "$in_statement" != "true" ]; then
                    in_statement="true"
                    STATEMENT_START_LINE=$LINE_NUMBER
                    CURRENT_STATEMENT="$line"
                else
                    # Add line to current statement
                    CURRENT_STATEMENT="$CURRENT_STATEMENT
$line"
                fi
                ;;
            *)
                if [ "$in_statement" = "true" ]; then
                    # Add line to current statement
                    CURRENT_STATEMENT="$CURRENT_STATEMENT
$line"
                else
                    # Line outside of statement
                    if [ "$PREVIEW_MODE" = "false" ]; then
                        $ECHO_CMD "$line"
                    fi
                    continue
                fi
                ;;
        esac
        
        # Check if statement is complete
        if [ "$in_statement" = "true" ] && is_statement_complete "$CURRENT_STATEMENT"; then
            # Process the complete statement
            process_sql_statement "$CURRENT_STATEMENT" "$last_set_schema"
            
            # Update last_set_schema if this was a SET SCHEMA statement
            stmt_upper=$(to_upper "$CURRENT_STATEMENT")
            stmt_upper_trimmed=$(echo "$stmt_upper" | sed 's/^[[:space:]]*//')
            case "$stmt_upper_trimmed" in
                "SET SCHEMA "*)
                    last_set_schema=$(echo "$stmt_upper_trimmed" | sed 's/^SET[[:space:]]\+SCHEMA[[:space:]]\+//' | awk '{print $1}' | sed 's/[;[:space:]]*$//')
                    ;;
            esac
            
            # Reset for next statement
            CURRENT_STATEMENT=""
            in_statement="false"
            STATEMENT_START_LINE=0
        fi
    done < "$file_path"
    
    # Handle any remaining incomplete statement
    if [ "$in_statement" = "true" ] && [ -n "$CURRENT_STATEMENT" ]; then
        process_sql_statement "$CURRENT_STATEMENT" "$last_set_schema"
    fi
    
    if [ "$PREVIEW_MODE" = "false" ]; then
        $ECHO_CMD ""
        $ECHO_CMD "-- End of file: $file_path"
        $ECHO_CMD ""
    else
        add_to_preview "======================================"
        add_to_preview ""
    fi
}

# Function to determine if input is a file list or single SQL file (portable)
process_input() {
    # Check if the input file contains SQL statements or file names
    first_line=$(head -n 1 "$INPUT_FILE" 2>/dev/null)
    first_line_upper=$(to_upper "$first_line")
    # Remove leading whitespace for pattern matching
    first_line_upper_trimmed=$(echo "$first_line_upper" | sed 's/^[[:space:]]*//')
    
    # Enhanced heuristic: if first line looks like SQL, treat as single file
    case "$first_line_upper_trimmed" in
        "CREATE "*|\
        "INSERT "*|\
        "UPDATE "*|\
        "DELETE "*|\
        "SELECT "*|\
        "WITH "*|\
        "SET "*|\
        "DROP "*|\
        "ALTER "*|\
        "GRANT "*|\
        "REVOKE "*|\
        "TRUNCATE "*|\
        "--"*|\
        "/"*)
            # Single SQL file
            add_to_summary "Processing single SQL file: $INPUT_FILE"
            process_sql_file "$INPUT_FILE"
            ;;
        *)
            # File list
            add_to_summary "Processing file list: $INPUT_FILE"
            while IFS= read -r file_path || [ -n "$file_path" ]; do
                # Skip empty lines and comments
                if [ -n "$file_path" ]; then
                    # Trim whitespace
                    file_path_trimmed=$(echo "$file_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    case "$file_path_trimmed" in
                        ""|"#"*)
                            continue
                            ;;
                        *)
                            process_sql_file "$file_path_trimmed"
                            ;;
                    esac
                fi
            done < "$INPUT_FILE"
            ;;
    esac
}

# Function to write summary (only in execute mode)
write_summary() {
    if [ "$PREVIEW_MODE" = "false" ]; then
        {
            $ECHO_CMD "=== SQL Processing Summary ==="
            $ECHO_CMD "Generated on: $($DATE_CMD)"
            $ECHO_CMD "Platform: $OS_TYPE"
            $ECHO_CMD "DBNAME: $DBNAME"
            $ECHO_CMD "SCHEMANAME: $SCHEMANAME"
            $ECHO_CMD "Input file: $INPUT_FILE"
            $ECHO_CMD "Output file: $OUTPUT_FILE"
            $ECHO_CMD ""
            $ECHO_CMD "Non-prod databases configured: $NON_PROD_DBS"
            $ECHO_CMD ""
            $ECHO_CMD "=== Processing Details ==="
            $ECHO_CMD "$SUMMARY_CONTENT"
            $ECHO_CMD ""
            $ECHO_CMD "=== End of Summary ==="
        } > "$SUMMARY_FILE"
    fi
}

# Function to display preview results
display_preview() {
    if [ "$PREVIEW_MODE" = "true" ]; then
        $ECHO_CMD ""
        $ECHO_CMD "======================================="
        $ECHO_CMD "           PREVIEW RESULTS"
        $ECHO_CMD "======================================="
        $ECHO_CMD ""
        $ECHO_CMD "Configuration:"
        $ECHO_CMD "  Platform: $OS_TYPE"
        $ECHO_CMD "  DBNAME: $DBNAME"
        $ECHO_CMD "  SCHEMANAME: $SCHEMANAME"
        $ECHO_CMD "  Input file: $INPUT_FILE"
        $ECHO_CMD ""
        $ECHO_CMD "Changes that would be made:"
        $ECHO_CMD "======================================="
        if [ -n "$PREVIEW_CHANGES" ]; then
            $ECHO_CMD "$PREVIEW_CHANGES"
        else
            $ECHO_CMD "No changes would be made to the SQL files."
        fi
        $ECHO_CMD ""
        $ECHO_CMD "Detailed analysis:"
        $ECHO_CMD "======================================="
        if [ -n "$SUMMARY_CONTENT" ]; then
            $ECHO_CMD "$SUMMARY_CONTENT"
        else
            $ECHO_CMD "No issues found."
        fi
        $ECHO_CMD ""
        $ECHO_CMD "======================================="
        $ECHO_CMD "Preview complete. No files were modified."
        $ECHO_CMD "To apply these changes, run the script with -preview=no"
    fi
}

# Function to cleanup temporary files
cleanup_temp() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR" 2>/dev/null
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_temp EXIT INT TERM

# Main execution
main() {
    # Detect platform and set commands
    detect_platform
    
    # Parse command line arguments first
    parse_arguments "$@"
    
    # Check if help is requested (already handled in parse_arguments, but keeping for safety)
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_usage
        exit 0
    fi
    
    # Get user inputs
    get_inputs
    
    # Process the input
    if [ "$PREVIEW_MODE" = "false" ]; then
        # Execute mode - generate output file
        {
            $ECHO_CMD "-- Combined SQL Output"
            $ECHO_CMD "-- Generated on: $($DATE_CMD)"
            $ECHO_CMD "-- Platform: $OS_TYPE"
            $ECHO_CMD "-- DBNAME: $DBNAME"
            $ECHO_CMD "-- SCHEMANAME: $SCHEMANAME"
            $ECHO_CMD "-- Source: $INPUT_FILE"
            $ECHO_CMD ""
            
            process_input
            
            $ECHO_CMD ""
            $ECHO_CMD "-- End of combined SQL output"
        } > "$OUTPUT_FILE"
        
        # Write summary
        write_summary
        
        # Display summary to stdout
        $ECHO_CMD "=== Processing Complete ==="
        $ECHO_CMD "Platform: $OS_TYPE"
        $ECHO_CMD "Output file: $OUTPUT_FILE"
        $ECHO_CMD "Summary file: $SUMMARY_FILE"
        $ECHO_CMD ""
        $ECHO_CMD "=== Summary ==="
        $ECHO_CMD "$SUMMARY_CONTENT"
        
        $ECHO_CMD ""
        $ECHO_CMD "Files generated:"
        $ECHO_CMD "  - $OUTPUT_FILE (combined SQL)"
        $ECHO_CMD "  - $SUMMARY_FILE (detailed summary)"
    else
        # Preview mode - just analyze and show preview
        process_input
        display_preview
    fi
    
    # Cleanup temporary files
    cleanup_temp
}

# Run the main function
main "$@"