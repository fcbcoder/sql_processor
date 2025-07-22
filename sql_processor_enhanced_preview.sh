#!/bin/bash

# SQL File Processor Script with Preview Mode
# Processes SQL files to add database/schema qualifiers and generate reports

# Configuration - Non-prod database names (easily configurable)
NON_PROD_DBS=("STGDV" "STGQA" "CIDDV" "CIDQA" "DEV" "TEST" "UAT")

# Global variables
DBNAME=""
SCHEMANAME=""
INPUT_FILE=""
OUTPUT_FILE=""
SUMMARY_FILE=""
SUMMARY_CONTENT=""
PREVIEW_MODE=false
LINE_NUMBER=0
CURRENT_FILE=""
CURRENT_STATEMENT=""
STATEMENT_START_LINE=0
PREVIEW_CHANGES=""

# Function to display usage
show_usage() {
    echo "Usage: $0 [-preview=yes|no] [-h|--help]"
    echo "This script processes SQL files to add database/schema qualifiers"
    echo ""
    echo "Options:"
    echo "  -preview=yes    Show preview of changes without modifying files"
    echo "  -preview=no     Make changes and generate output files (default)"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "You will be prompted for:"
    echo "  - DBNAME: Target database name"
    echo "  - SCHEMANAME: Target schema name" 
    echo "  - Input: Single SQL file OR file containing list of SQL files"
    echo ""
}

# Function to parse command line arguments
parse_arguments() {
    for arg in "$@"; do
        case $arg in
            -preview=yes)
                PREVIEW_MODE=true
                shift
                ;;
            -preview=no)
                PREVIEW_MODE=false
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                # Unknown option
                echo "Unknown option: $arg"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to prompt for inputs
get_inputs() {
    echo "=== SQL File Processor ==="
    if [[ "$PREVIEW_MODE" == true ]]; then
        echo "=== PREVIEW MODE - No files will be modified ==="
    fi
    echo ""
    
    # Get database name
    while [[ -z "$DBNAME" ]]; do
        read -p "Enter DBNAME (target database name): " DBNAME
        if [[ -z "$DBNAME" ]]; then
            echo "DBNAME cannot be empty. Please try again."
        fi
    done
    
    # Get schema name
    while [[ -z "$SCHEMANAME" ]]; do
        read -p "Enter SCHEMANAME (target schema name): " SCHEMANAME
        if [[ -z "$SCHEMANAME" ]]; then
            echo "SCHEMANAME cannot be empty. Please try again."
        fi
    done
    
    # Get input file
    while [[ -z "$INPUT_FILE" ]]; do
        read -p "Enter input file (single SQL file or file containing list of SQL files): " INPUT_FILE
        if [[ ! -f "$INPUT_FILE" ]]; then
            echo "File '$INPUT_FILE' not found. Please try again."
            INPUT_FILE=""
        fi
    done
    
    # Set output files (only if not in preview mode)
    if [[ "$PREVIEW_MODE" == false ]]; then
        OUTPUT_FILE="combined_output_$(date +%Y%m%d_%H%M%S).sql"
        SUMMARY_FILE="processing_summary_$(date +%Y%m%d_%H%M%S).txt"
    else
        OUTPUT_FILE="[PREVIEW MODE - No output file will be created]"
        SUMMARY_FILE="[PREVIEW MODE - No summary file will be created]"
    fi
    
    echo ""
    echo "Configuration:"
    echo "  Mode: $(if [[ "$PREVIEW_MODE" == true ]]; then echo "PREVIEW"; else echo "EXECUTE"; fi)"
    echo "  DBNAME: $DBNAME"
    echo "  SCHEMANAME: $SCHEMANAME"
    echo "  Input file: $INPUT_FILE"
    echo "  Output file: $OUTPUT_FILE"
    echo "  Summary file: $SUMMARY_FILE"
    echo ""
}

# Function to check if a database name is non-prod (case-insensitive)
is_non_prod_db() {
    local db_name="$1"
    local db_name_upper=$(echo "$db_name" | tr '[:lower:]' '[:upper:]')
    for non_prod in "${NON_PROD_DBS[@]}"; do
        local non_prod_upper=$(echo "$non_prod" | tr '[:lower:]' '[:upper:]')
        if [[ "$db_name_upper" == "$non_prod_upper" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to add to summary
add_to_summary() {
    local message="$1"
    SUMMARY_CONTENT="$SUMMARY_CONTENT$message\n"
}

# Function to add to preview changes
add_to_preview() {
    local message="$1"
    PREVIEW_CHANGES="$PREVIEW_CHANGES$message\n"
}

# Function to extract database and schema from qualified name
extract_db_schema() {
    local qualified_name="$1"
    local db_part=""
    local schema_part=""
    local object_part=""
    
    # Remove any trailing parentheses, commas, or other characters
    qualified_name=$(echo "$qualified_name" | sed 's/[(),;[:space:]]*$//')
    
    # Count dots to determine format
    local dot_count=$(echo "$qualified_name" | tr -cd '.' | wc -c)
    
    if [[ $dot_count -eq 2 ]]; then
        # Format: db.schema.object
        db_part=$(echo "$qualified_name" | cut -d'.' -f1)
        schema_part=$(echo "$qualified_name" | cut -d'.' -f2)
        object_part=$(echo "$qualified_name" | cut -d'.' -f3)
    elif [[ $dot_count -eq 1 ]]; then
        # Format: schema.object
        schema_part=$(echo "$qualified_name" | cut -d'.' -f1)
        object_part=$(echo "$qualified_name" | cut -d'.' -f2)
    else
        # Format: object
        object_part="$qualified_name"
    fi
    
    echo "$db_part|$schema_part|$object_part"
}

# Function to check if a statement is complete (ends with semicolon)
is_statement_complete() {
    local statement="$1"
    # Remove comments and whitespace, then check if it ends with semicolon
    local cleaned_statement=$(echo "$statement" | sed 's/--.*$//' | sed 's/[[:space:]]*$//')
    # Use a simpler pattern match instead of regex
    [[ "$cleaned_statement" == *";" ]]
}

# Enhanced function to identify SQL statement type and extract object name (case-insensitive)
identify_statement_type() {
    local statement="$1"
    local statement_upper=$(echo "$statement" | tr '[:lower:]' '[:upper:]')
    
    # Remove comments and extra whitespace
    statement_upper=$(echo "$statement_upper" | sed 's/--.*$//' | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//')
    
    local stmt_type=""
    local object_name=""
    
    # Enhanced regex patterns with better whitespace handling
    if [[ "$statement_upper" =~ ^CREATE[[:space:]]+TABLE[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="CREATE TABLE"
        object_name="${BASH_REMATCH[1]}"
    elif [[ "$statement_upper" =~ ^CREATE[[:space:]]+OR[[:space:]]+REPLACE[[:space:]]+VIEW[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="CREATE OR REPLACE VIEW"
        object_name="${BASH_REMATCH[1]}"
    elif [[ "$statement_upper" =~ ^CREATE[[:space:]]+VIEW[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="CREATE VIEW"
        object_name="${BASH_REMATCH[1]}"
    elif [[ "$statement_upper" =~ ^CREATE[[:space:]]+INDEX[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="CREATE INDEX"
        object_name="${BASH_REMATCH[1]}"
    elif [[ "$statement_upper" =~ ^CREATE[[:space:]]+UNIQUE[[:space:]]+INDEX[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="CREATE UNIQUE INDEX"
        object_name="${BASH_REMATCH[1]}"
    elif [[ "$statement_upper" =~ ^CREATE[[:space:]]+PROCEDURE[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="CREATE PROCEDURE"
        object_name="${BASH_REMATCH[1]}"
    elif [[ "$statement_upper" =~ ^CREATE[[:space:]]+FUNCTION[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="CREATE FUNCTION"
        object_name="${BASH_REMATCH[1]}"
    elif [[ "$statement_upper" =~ ^DROP[[:space:]]+TABLE[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="DROP TABLE"
        object_name="${BASH_REMATCH[1]}"
    elif [[ "$statement_upper" =~ ^DROP[[:space:]]+VIEW[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="DROP VIEW"
        object_name="${BASH_REMATCH[1]}"
    elif [[ "$statement_upper" =~ ^DROP[[:space:]]+INDEX[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="DROP INDEX"
        object_name="${BASH_REMATCH[1]}"
    elif [[ "$statement_upper" =~ ^ALTER[[:space:]]+TABLE[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="ALTER TABLE"
        object_name="${BASH_REMATCH[1]}"
    elif [[ "$statement_upper" =~ ^INSERT[[:space:]]+INTO[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="INSERT INTO"
        object_name="${BASH_REMATCH[1]}"
    elif [[ "$statement_upper" =~ ^UPDATE[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="UPDATE"
        object_name="${BASH_REMATCH[1]}"
    elif [[ "$statement_upper" =~ ^DELETE[[:space:]]+FROM[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="DELETE FROM"
        object_name="${BASH_REMATCH[1]}"
    elif [[ "$statement_upper" =~ ^TRUNCATE[[:space:]]+TABLE[[:space:]]+([^[:space:],()]+) ]]; then
        stmt_type="TRUNCATE TABLE"
        object_name="${BASH_REMATCH[1]}"
    fi
    
    echo "$stmt_type|$object_name"
}

# Enhanced function to find cross-database references in FROM/JOIN clauses (case-insensitive)
find_cross_db_references() {
    local statement="$1"
    local statement_upper=$(echo "$statement" | tr '[:lower:]' '[:upper:]')
    
    # Extract all FROM/JOIN references using a more comprehensive regex
    local refs=()
    
    # Find FROM clauses - enhanced pattern matching
    while [[ "$statement_upper" =~ FROM[[:space:]]+([^[:space:],()]+) ]]; do
        refs+=("${BASH_REMATCH[1]}")
        statement_upper=${statement_upper/${BASH_REMATCH[0]}/}
    done
    
    # Find JOIN clauses - enhanced pattern matching
    statement_upper=$(echo "$statement" | tr '[:lower:]' '[:upper:]')
    while [[ "$statement_upper" =~ (INNER[[:space:]]+JOIN|LEFT[[:space:]]+OUTER[[:space:]]+JOIN|RIGHT[[:space:]]+OUTER[[:space:]]+JOIN|FULL[[:space:]]+OUTER[[:space:]]+JOIN|LEFT[[:space:]]+JOIN|RIGHT[[:space:]]+JOIN|FULL[[:space:]]+JOIN|CROSS[[:space:]]+JOIN|JOIN)[[:space:]]+([^[:space:],()]+) ]]; do
        refs+=("${BASH_REMATCH[2]}")
        statement_upper=${statement_upper/${BASH_REMATCH[0]}/}
    done
    
    # Check each reference for cross-database usage
    for ref_obj in "${refs[@]}"; do
        local ref_db_schema_obj=$(extract_db_schema "$ref_obj")
        local ref_db_part=$(echo "$ref_db_schema_obj" | cut -d'|' -f1)
        
        if [[ -n "$ref_db_part" && "$(echo "$ref_db_part" | tr '[:lower:]' '[:upper:]')" != "$(echo "$DBNAME" | tr '[:lower:]' '[:upper:]')" ]]; then
            if is_non_prod_db "$ref_db_part"; then
                add_to_summary "WARNING: File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - NON-PROD database reference found: $ref_db_part in object $ref_obj"
                if [[ "$PREVIEW_MODE" == true ]]; then
                    add_to_preview "⚠️  WARNING: Non-prod database reference '$ref_db_part' found in $ref_obj"
                fi
            else
                add_to_summary "INFO: File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - Cross-database reference found: $ref_db_part in object $ref_obj"
                if [[ "$PREVIEW_MODE" == true ]]; then
                    add_to_preview "ℹ️  INFO: Cross-database reference '$ref_db_part' found in $ref_obj"
                fi
            fi
        fi
    done
}

# Enhanced function to process a complete SQL statement (case-insensitive)
process_sql_statement() {
    local statement="$1"
    local last_set_schema="$2"
    local processed_statement="$statement"
    local set_schema_line=""
    local needs_semicolon=false
    local changes_made=false
    
    # Skip empty statements
    local cleaned_statement=$(echo "$statement" | sed 's/--.*$//' | sed 's/[[:space:]]*$//' | tr -d '\n\r')
    if [[ -z "$cleaned_statement" ]]; then
        if [[ "$PREVIEW_MODE" == false ]]; then
            echo "$statement"
        fi
        return
    fi
    
    # Check if this is a SET SCHEMA statement (case-insensitive)
    local stmt_upper=$(echo "$statement" | tr '[:lower:]' '[:upper:]')
    if [[ "$stmt_upper" =~ ^[[:space:]]*SET[[:space:]]+SCHEMA[[:space:]]+([^[:space:];]+) ]]; then
        # This is already a SET SCHEMA statement, just output it
        local existing_schema="${BASH_REMATCH[1]}"
        add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - Found existing SET SCHEMA $existing_schema"
        
        # Add semicolon if needed
        if ! is_statement_complete "$statement"; then
            processed_statement="$processed_statement;"
            add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - Added missing semicolon to SET SCHEMA"
            if [[ "$PREVIEW_MODE" == true ]]; then
                add_to_preview "📝 Line $STATEMENT_START_LINE-$LINE_NUMBER: Would add missing semicolon to SET SCHEMA"
            fi
            changes_made=true
        fi
        
        if [[ "$PREVIEW_MODE" == false ]]; then
            echo "$processed_statement"
        elif [[ "$changes_made" == true ]]; then
            add_to_preview "   Before: ${statement%$'\n'}"
            add_to_preview "   After:  ${processed_statement%$'\n'}"
        fi
        return
    fi
    
    # Check if statement ends with semicolon
    if ! is_statement_complete "$statement"; then
        needs_semicolon=true
    fi
    
    # Identify statement type and object
    local stmt_info=$(identify_statement_type "$statement")
    local stmt_type=$(echo "$stmt_info" | cut -d'|' -f1)
    local object_name=$(echo "$stmt_info" | cut -d'|' -f2)
    
    # Process DDL/DML statements
    if [[ -n "$stmt_type" && -n "$object_name" ]]; then
        # Parse the object name
        local db_schema_obj=$(extract_db_schema "$object_name")
        local db_part=$(echo "$db_schema_obj" | cut -d'|' -f1)
        local schema_part=$(echo "$db_schema_obj" | cut -d'|' -f2)
        local obj_part=$(echo "$db_schema_obj" | cut -d'|' -f3)
        
        # Determine what to do based on current format
        if [[ -n "$db_part" && -n "$schema_part" ]]; then
            # Already has db.schema.object format
            add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - $stmt_type statement already has DBNAME ($db_part) - no modification needed"
            # Only add SET SCHEMA if it's different from the last one (case-insensitive comparison)
            if [[ "$(echo "$schema_part" | tr '[:lower:]' '[:upper:]')" != "$(echo "$last_set_schema" | tr '[:lower:]' '[:upper:]')" ]]; then
                set_schema_line="SET SCHEMA $schema_part;"
                if [[ "$PREVIEW_MODE" == true ]]; then
                    add_to_preview "📝 Line $STATEMENT_START_LINE: Would add SET SCHEMA $schema_part;"
                fi
                changes_made=true
            else
                add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - SET SCHEMA $schema_part already in effect, skipping"
            fi
        elif [[ -n "$schema_part" ]]; then
            # Has schema.object format - add database
            local new_object_name="$DBNAME.$schema_part.$obj_part"
            # Use case-insensitive replacement
            processed_statement=$(echo "$processed_statement" | sed "s/\b$object_name\b/$new_object_name/gi")
            add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - Added DBNAME to $stmt_type: $object_name -> $new_object_name"
            if [[ "$PREVIEW_MODE" == true ]]; then
                add_to_preview "📝 Line $STATEMENT_START_LINE-$LINE_NUMBER: Would change $stmt_type object: $object_name -> $new_object_name"
            fi
            changes_made=true
            # Only add SET SCHEMA if it's different from the last one (case-insensitive comparison)
            if [[ "$(echo "$schema_part" | tr '[:lower:]' '[:upper:]')" != "$(echo "$last_set_schema" | tr '[:lower:]' '[:upper:]')" ]]; then
                set_schema_line="SET SCHEMA $schema_part;"
                if [[ "$PREVIEW_MODE" == true ]]; then
                    add_to_preview "📝 Line $STATEMENT_START_LINE: Would add SET SCHEMA $schema_part;"
                fi
            else
                add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - SET SCHEMA $schema_part already in effect, skipping"
            fi
        else
            # Has only object format - add database and schema
            local new_object_name="$DBNAME.$SCHEMANAME.$obj_part"
            # Use case-insensitive replacement
            processed_statement=$(echo "$processed_statement" | sed "s/\b$object_name\b/$new_object_name/gi")
            add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - Added DBNAME.SCHEMANAME to $stmt_type: $object_name -> $new_object_name"
            if [[ "$PREVIEW_MODE" == true ]]; then
                add_to_preview "📝 Line $STATEMENT_START_LINE-$LINE_NUMBER: Would change $stmt_type object: $object_name -> $new_object_name"
            fi
            changes_made=true
            # Only add SET SCHEMA if it's different from the last one (case-insensitive comparison)
            if [[ "$(echo "$SCHEMANAME" | tr '[:lower:]' '[:upper:]')" != "$(echo "$last_set_schema" | tr '[:lower:]' '[:upper:]')" ]]; then
                set_schema_line="SET SCHEMA $SCHEMANAME;"
                if [[ "$PREVIEW_MODE" == true ]]; then
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
    if [[ "$needs_semicolon" == true ]]; then
        processed_statement="$processed_statement;"
        add_to_summary "File: $CURRENT_FILE, Lines: $STATEMENT_START_LINE-$LINE_NUMBER - Added missing semicolon"
        if [[ "$PREVIEW_MODE" == true ]]; then
            add_to_preview "📝 Line $STATEMENT_START_LINE-$LINE_NUMBER: Would add missing semicolon"
        fi
        changes_made=true
    fi
    
    # In preview mode, show before/after if changes were made
    if [[ "$PREVIEW_MODE" == true && "$changes_made" == true ]]; then
        add_to_preview "   Before: ${statement%$'\n'}"
        add_to_preview "   After:  $(if [[ -n "$set_schema_line" ]]; then echo "$set_schema_line"; fi)${processed_statement%$'\n'}"
        add_to_preview ""
    fi
    
    # Output in execute mode
    if [[ "$PREVIEW_MODE" == false ]]; then
        # Output SET SCHEMA line if needed
        if [[ -n "$set_schema_line" ]]; then
            echo "$set_schema_line"
        fi
        
        # Output the processed statement
        echo "$processed_statement"
    fi
}

# Function to process a single SQL file
process_sql_file() {
    local file_path="$1"
    
    if [[ ! -f "$file_path" ]]; then
        add_to_summary "ERROR: File not found: $file_path"
        return 1
    fi
    
    CURRENT_FILE="$file_path"
    add_to_summary "Processing file: $file_path"
    
    if [[ "$PREVIEW_MODE" == true ]]; then
        add_to_preview "🔍 Analyzing file: $file_path"
        add_to_preview "======================================"
    else
        echo "-- File: $file_path"
        echo "-- Processed on: $(date)"
        echo ""
    fi
    
    LINE_NUMBER=0
    CURRENT_STATEMENT=""
    STATEMENT_START_LINE=0
    local in_statement=false
    local last_set_schema=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((LINE_NUMBER++))
        
        # Remove carriage return characters (Windows line endings)
        line=$(echo "$line" | tr -d '\r')
        
        # Skip pure comment lines and empty lines when not in a statement
        if [[ ! "$in_statement" == true ]] && [[ -z "$line" || "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*-- ]]; then
            if [[ "$PREVIEW_MODE" == false ]]; then
                echo "$line"
            fi
            continue
        fi
        
        # Check if this line starts a new SQL statement (case-insensitive)
        local line_upper=$(echo "$line" | tr '[:lower:]' '[:upper:]')
        if [[ ! "$in_statement" == true ]] && [[ "$line_upper" =~ ^[[:space:]]*(CREATE|INSERT|UPDATE|DELETE|SELECT|WITH|SET|DROP|ALTER|GRANT|REVOKE|TRUNCATE) ]]; then
            in_statement=true
            STATEMENT_START_LINE=$LINE_NUMBER
            CURRENT_STATEMENT="$line"
        elif [[ "$in_statement" == true ]]; then
            # Add line to current statement
            CURRENT_STATEMENT="$CURRENT_STATEMENT"$'\n'"$line"
        else
            # Line outside of statement (shouldn't happen often)
            if [[ "$PREVIEW_MODE" == false ]]; then
                echo "$line"
            fi
            continue
        fi
        
        # Check if statement is complete
        if [[ "$in_statement" == true ]] && is_statement_complete "$CURRENT_STATEMENT"; then
            # Process the complete statement
            process_sql_statement "$CURRENT_STATEMENT" "$last_set_schema"
            
            # Update last_set_schema if this was a SET SCHEMA statement (case-insensitive)
            local stmt_upper=$(echo "$CURRENT_STATEMENT" | tr '[:lower:]' '[:upper:]')
            if [[ "$stmt_upper" =~ ^[[:space:]]*SET[[:space:]]+SCHEMA[[:space:]]+([^[:space:];]+) ]]; then
                last_set_schema="${BASH_REMATCH[1]}"
            fi
            
            # Reset for next statement
            CURRENT_STATEMENT=""
            in_statement=false
            STATEMENT_START_LINE=0
        fi
    done < "$file_path"
    
    # Handle any remaining incomplete statement
    if [[ "$in_statement" == true && -n "$CURRENT_STATEMENT" ]]; then
        process_sql_statement "$CURRENT_STATEMENT" "$last_set_schema"
    fi
    
    if [[ "$PREVIEW_MODE" == false ]]; then
        echo ""
        echo "-- End of file: $file_path"
        echo ""
    else
        add_to_preview "======================================"
        add_to_preview ""
    fi
}

# Enhanced function to determine if input is a file list or single SQL file (case-insensitive)
process_input() {
    # Check if the input file contains SQL statements or file names
    local first_line=$(head -n 1 "$INPUT_FILE" 2>/dev/null)
    local first_line_upper=$(echo "$first_line" | tr '[:lower:]' '[:upper:]')
    
    # Enhanced heuristic: if first line looks like SQL, treat as single file
    # Otherwise, treat as file list
    if [[ "$first_line_upper" =~ ^[[:space:]]*(CREATE|INSERT|UPDATE|DELETE|SELECT|WITH|SET|DROP|ALTER|GRANT|REVOKE|TRUNCATE|--|\/) ]]; then
        # Single SQL file
        add_to_summary "Processing single SQL file: $INPUT_FILE"
        process_sql_file "$INPUT_FILE"
    else
        # File list
        add_to_summary "Processing file list: $INPUT_FILE"
        while IFS= read -r file_path || [[ -n "$file_path" ]]; do
            # Skip empty lines and comments
            if [[ -n "$file_path" && ! "$file_path" =~ ^[[:space:]]*# ]]; then
                process_sql_file "$file_path"
            fi
        done < "$INPUT_FILE"
    fi
}

# Function to write summary (only in execute mode)
write_summary() {
    if [[ "$PREVIEW_MODE" == false ]]; then
        {
            echo "=== SQL Processing Summary ==="
            echo "Generated on: $(date)"
            echo "DBNAME: $DBNAME"
            echo "SCHEMANAME: $SCHEMANAME"
            echo "Input file: $INPUT_FILE"
            echo "Output file: $OUTPUT_FILE"
            echo ""
            echo "Non-prod databases configured: ${NON_PROD_DBS[*]}"
            echo ""
            echo "=== Processing Details ==="
            echo -e "$SUMMARY_CONTENT"
            echo ""
            echo "=== End of Summary ==="
        } > "$SUMMARY_FILE"
    fi
}

# Function to display preview results
display_preview() {
    if [[ "$PREVIEW_MODE" == true ]]; then
        echo ""
        echo "======================================="
        echo "           PREVIEW RESULTS"
        echo "======================================="
        echo ""
        echo "Configuration:"
        echo "  DBNAME: $DBNAME"
        echo "  SCHEMANAME: $SCHEMANAME"
        echo "  Input file: $INPUT_FILE"
        echo ""
        echo "Changes that would be made:"
        echo "======================================="
        if [[ -n "$PREVIEW_CHANGES" ]]; then
            echo -e "$PREVIEW_CHANGES"
        else
            echo "No changes would be made to the SQL files."
        fi
        echo ""
        echo "Detailed analysis:"
        echo "======================================="
        if [[ -n "$SUMMARY_CONTENT" ]]; then
            echo -e "$SUMMARY_CONTENT"
        else
            echo "No issues found."
        fi
        echo ""
        echo "======================================="
        echo "Preview complete. No files were modified."
        echo "To apply these changes, run the script with -preview=no"
    fi
}

# Main execution
main() {
    # Parse command line arguments first
    parse_arguments "$@"
    
    # Check if help is requested (already handled in parse_arguments, but keeping for safety)
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    # Get user inputs
    get_inputs
    
    # Process the input
    if [[ "$PREVIEW_MODE" == false ]]; then
        # Execute mode - generate output file
        {
            echo "-- Combined SQL Output"
            echo "-- Generated on: $(date)"
            echo "-- DBNAME: $DBNAME"
            echo "-- SCHEMANAME: $SCHEMANAME"
            echo "-- Source: $INPUT_FILE"
            echo ""
            
            process_input
            
            echo ""
            echo "-- End of combined SQL output"
        } > "$OUTPUT_FILE"
        
        # Write summary
        write_summary
        
        # Display summary to stdout
        echo "=== Processing Complete ==="
        echo "Output file: $OUTPUT_FILE"
        echo "Summary file: $SUMMARY_FILE"
        echo ""
        echo "=== Summary ==="
        echo -e "$SUMMARY_CONTENT"
        
        echo ""
        echo "Files generated:"
        echo "  - $OUTPUT_FILE (combined SQL)"
        echo "  - $SUMMARY_FILE (detailed summary)"
    else
        # Preview mode - just analyze and show preview
        process_input
        display_preview
    fi
}

# Run the main function
main "$@"
        