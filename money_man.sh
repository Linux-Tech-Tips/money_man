#!/bin/bash

# Money Man v1 utility for monetary tracking/statistics management
# Functionality:
#  - Multiple accounts
#  - In each account, multiple months
#  - In each month, financial data in table available
#  - From each month, statistics about spending/earning can be generated
#  - Each transaction can be assigned a category from a user-defined list
#  - The monthly logs can be printed in a fancy table, optimally with category colors
#  - The monthly logs can be exported into a CSV format, so that it can be imported into any standard editing software
#  - Any CSV logs can be imported into this program into any month

# Program:
# money_man.sh [name of project directory to use]
#  - interactive shell until the user exits, basically with commands
#  - terminal: `[no account/no month]> `
#
# Commands:
#  - help ............................... shows help info
#  - acc ................................ shows existing accounts
#  - acc [account name] ................. sets the current account to be the given account name, if nonexistent, creates new account
#  - list ............................... lists tables in the account, typically this would be months
#  - select <table name> ................ selects the current table from the account
#  - print [num lines] .................. prints num lines of content from the current table, or all if blank or <0, sorted by date
#  - add <desc> <amount> <tag> <date> ... adds a line to the table with the given info, use quotes for spaces
#  - rm <id> ............................ removes the line with the specified ID
#  - tag ................................ shows existing tags available for entries
#  - tag [tag name] ..................... shows details about existing tag or creates new if nonexistent
#  - export [file name] ................. exports the current table from the current account into a file with the given name
#  - import <csv name> .................. imports the rows from the given CSV file (if compatible) into the current table in the current account


# FUNCTIONS

programHelp() {
    echo "money_man.sh program"
    echo ""
    echo "usage: money_man.sh [project directory]"
    echo " - starts the money_man interactive terminal program"
    echo " - if project directory specified, that project directory is used instead of the default"
}

# Sets up the directory given in $1 as a project directory
verifyDir() {

    # Try to create folder if it doesn't exist
    [[ -e "${1}" ]] || {
	mkdir -p "${1}"
    }

    # Test directory permissions
    [[ -d "${1}" && -r "${1}" && -w "${1}" ]] || {
	echo "Error: Project permissions incorrect"
	return 1
    }

    return 0
}

# Verify that ACC variable isn't "none"
verifyAcc() {
    [[ "${ACC}" == "none" ]] && {
	echo "Please select account (using 'acc [account name]')"
	return 1
    }
    return 0
}

# Verify that TABLE variable isn't "none"
verifyTable() {
    [[ "${TABLE}" == "none" ]] && {
	echo "Please select table (using 'select <table name>')"
	return 1
    }
    return 0
}


# PROGRAM SECTION

[[ $# -gt 1 || "${1}" == "--help" || "${1}" == "-h" ]] && {
    programHelp
    exit 0;
}

# Program variables (environment-exportable configuration)
[[ -z "${ACC_FILE}" ]] && ACC_FILE="accounts.dat"
[[ -z "${TAG_FILE}" ]] && TAG_FILE="tags.dat"

# Get project directory and verify permissions
DIR="${1}"
[[ -z ${dir} ]] && DIR=".money_man_data"

verifyDir "${DIR}" || exit 1

# Start program
declare RUN_DIR="$(pwd)"
pushd "${DIR}"
echo "Money Man Program v1 Bash"
echo "type 'help' for information"
echo ""

declare ACC="none"
declare TABLE="none"
declare TABLE_FILE=

# TODO:
#  - Add account features: account metadata files
#    - Starting monetary amount in account
#    - Tables being ordered in the account chronologically
#    - Totals either for all tables, or up to a certain table
#    - Statistics for all account
#    - Statistics for specific table
#  - Add QOL features:
#    - Removing accounts
#    - Removing tags
#    - Table file validation at select to clear files if anything invalid
#    - Command history

# Main program loop
while read -ep "[${ACC}/${TABLE}]> " LINE
do
    # Parse line into array, taking quotes into consideration
    parsed=()
    eval "for arg in $LINE; do parsed+=(\"\$arg\"); done"
    cmd="${parsed[0]}"

    # Command handling
    case "${cmd}" in
	exit|quit)
	    echo "Exitting..."
	    exit 0
	;;

	help)
	    echo "Money Man Help Menu"
	    echo "Available Commands:"
	    echo " - help ............................... shows help info"
	    echo " - acc ................................ shows existing accounts"
	    echo " - acc [account name] ................. sets the current account to be the given account name, if nonexistent, creates new account"
	    echo " - list ............................... lists tables in the account, typically this would be months"
	    echo " - select <table name> ................ selects the specified table from the account, if nonexistent, creates new table"
	    echo " - print [num lines] .................. prints num lines of content from the current table, or all if blank or <0, sorted by date"
	    echo " - add <desc> <amount> <tag> <date> ... adds a line to the table with the given info, use quotes for spaces"
	    echo " - rm <id to remove> .................. removes the line with the specified ID"
	    echo " - tag ................................ shows existing tags available for entries"
	    echo " - tag [tag name] ..................... shows details about existing tag or creates new if nonexistent"
	    echo " - export [file name] ................. exports the current table from the current account into a file with the given name"
	    echo " - import <csv name> .................. imports the rows from the given CSV file (if compatible) into the current table in the current account"
	;;

	acc)
	    # Setup accounts file if nonexistent
	    [[ -e "${ACC_FILE}" ]] || {
		touch "${ACC_FILE}" || {
		    # Error reporting if file can't be created
		    echo "Error: Could not create Accounts file and none exists"
		    continue
		}
	    }
	    # Use accounts file
	    [[ ${#parsed[@]} -gt 1 ]] && {
		# Use (or Add) account
		grep -q "^${parsed[1]}$" "${ACC_FILE}" || {
		    # Add Account Case
		    read -p "Account ${parsed[1]} not found. Create? (y/n) "
		    [[ "$REPLY" == "y"* || "$REPLY" == "Y"* ]] && {
			echo "${parsed[1]}" >> "${ACC_FILE}"
			echo "Created account ${parsed[1]}"
		    } || {
			echo "Cancelled"
			continue
		    }
		}
		# Use current account
		ACC="${parsed[1]}"
		# Reset selected table
		TABLE="none"
		TABLE_FILE=
	    } || {
		# Display all existing accounts
		echo "Existing Accounts:"
		cat "${ACC_FILE}"
	    }
	;;

	list)
	    # If account selected, list all tables in account
	    verifyAcc || continue
	    find . -name "${ACC}-*" | sed "s/\.\/${ACC}-\(.*\)\.csv/\1/"
	;;

	select)
	    # If specified and exists, selects the desired table in the current account
	    [[ ${#parsed[@]} -lt 2 ]] && {
		echo "Please provide table to select"
		continue
	    }
	    verifyAcc || continue

	    # Selecting desired table and checking if present
	    tableFile="./${ACC}-${parsed[1]}.csv"
	    [[ -e "${tableFile}" ]] || {
		read -p "Table '${parsed[1]}' not found. Create? (y/n) "
		[[ "$REPLY" == "y"* || "$REPLY" == "Y"* ]] && {
		    touch "${tableFile}"
		    echo "Created account ${parsed[1]}"
		} || {
		    echo "Cancelled"
		    continue
		}
	    }
	    TABLE="${parsed[1]}"
	    TABLE_FILE="${tableFile}"
	;;

	print)
	    # Check if table selected
	    verifyTable || continue

	    # Print N lines
	    [[ -z "${parsed[1]}" ]] && {
		sort -k5r -t"," "${TABLE_FILE}" | column -s"," -N"ID,Description,Amount,Tag,Date" -o" | " -t
	    } || {
		sort -k5r -t"," "${TABLE_FILE}" | column -s"," -N"ID,Description,Amount,Tag,Date" -o" | " -t | head -n $((${parsed[1]}+1))
	    }
	;;

	add)
	    # Validate add command
	    verifyTable || continue
	    [[ ${#parsed[@]} -ne 5 ]] && {
		echo "Please use specified add format: 'add <desc> <amount> <tag> <date>'"
		continue
	    }

	    # Validate if tag exists
	    grep -q "^${parsed[3]}$" "${TAG_FILE}" || {
		echo "Tag ${parsed[3]} not found. See existing tags using 'tag' or create a new one using 'tag [name]'"
		continue
	    }

	    # Get last line ID
	    lastID=$(sort -k1r "${TABLE_FILE}" | head -n1 | sed -ne "s/^\([0-9]\+\),.*/\1/p")
	    ID=$((${lastID} + 1))
	    # Add line
	    echo "${ID}, ${parsed[1]}, ${parsed[2]}, ${parsed[3]}, ${parsed[4]}" >> "${TABLE_FILE}"
	;;

	rm)
	    # Validate rm command
	    verifyTable || continue
	    [[ ${#parsed[@]} -ne 2 ]] && {
		echo "Please use specified rm format: 'rm <id to remove>'"
		continue
	    }
	    grep -q "^${parsed[1]}," "${TABLE_FILE}" || {
		echo "ID ${parsed[1]} not found in table ${TABLE}"
		continue
	    }
	    
	    # Remove record from table file
	    sed -e "/^${parsed[1]},/d" -i "${TABLE_FILE}"
	;;

	tag)
	    # Setup accounts file if nonexistent
	    [[ -e "${TAG_FILE}" ]] || {
		touch "${TAG_FILE}" || {
		    # Error reporting if file can't be created
		    echo "Error: Could not create Tags file and none exists"
		    continue
		}
	    } 
	    # Use tags file
	    [[ ${#parsed[@]} -gt 1 ]] && {
		# Display (or Add) tag
		grep -q "^${parsed[1]}$" "${TAG_FILE}" || {
		    # Add Tag Case
		    read -p "Tag ${parsed[1]} not found. Create? (y/n) "
		    [[ "$REPLY" == "y"* || "$REPLY" == "Y"* ]] && {
			echo "${parsed[1]}" >> "${TAG_FILE}"
			echo "Created tag ${parsed[1]}"
		    } || {
			echo "Cancelled"
			continue
		    }
		}
		# Display tag
		echo "Tag exists: '${parsed[1]}'"
	    } || {
		# Display all existing accounts
		echo "Existing Tags:"
		cat "${TAG_FILE}"
	    }
	;;

	export)
	    # Verify that table to export exists
	    verifyTable || continue

	    # Exporting table to file with an appropriate name
	    expName=$([[ ${#parsed[@]} -lt 2 ]] && echo "${TABLE}.csv" || echo "${parsed[1]}")
	    expName="${RUN_DIR}/${expName}"
	    cp "${TABLE_FILE}" "${expName}"

	    # Let the user know where the exported table is
	    echo "Exported table ${TABLE} to ${expName}"
	;;

	import)
	    # Verify that table to import into selected
	    verifyTable || continue

	    # Validate file argument
	    file="${RUN_DIR}/${parsed[1]}"
	    [[ -f "${file}" ]] || {
		echo "Please specify a valid file to import (file '${file}' is not valid)"
		continue
	    }

	    # Get biggest/last ID
	    ID=$(sort -k1r "${TABLE_FILE}" | head -n1 | sed -ne "s/^\([0-9]\+\),.*/\1/p")

	    # Import lines from given file into current table, using ID based on current table
	    while read line
	    do
		[[ -z "${line}" ]] || {
		    ID=$((${ID} + 1))
		    echo "${ID}, $(sed -ne "s/^[0-9]\+,\s*\(.*\)/\1/p" <<< "${line}")" >> "${TABLE_FILE}"
		}
	    done < "${file}"

	    # Let the user know what import happened where
	    echo "Imported table '${file}' into the currently selected table '${TABLE}'"
	;;

	*)
	    echo "Error: Command '${cmd}' not recognized. Try help"
    esac

    # Clearing line for the next read call
    LINE=

done

