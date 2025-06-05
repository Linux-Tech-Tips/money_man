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

# Statistics stuff
# The stats should be definable using a declaration oriented data manipulation language
# Commands:
#   - group <name | amount | tag | date>
#   - ungroup
#   - check <EXPR>
#   - collapse <avg | min | max | sum | count>
#   - select <name | amount | tag | date>
# Executed one after another
# How to make this:
#   - group will be done using folders and subfiles, then check for each line in file, collapse for each file, select for each file


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
	echo "Error: Project permissions incorrect" >&2
	return 1
    }

    return 0
}

# Verify that ACC variable isn't "none"
verifyAcc() {
    [[ "${ACC}" == "none" ]] && {
	echo "Please select account (using 'acc [account name]')" >&2
	return 1
    }
    return 0
}

# Verify that TABLE variable isn't "none"
verifyTable() {
    [[ "${TABLE}" == "none" ]] && {
	echo "Please select table (using 'select <table name>')" >&2
	return 1
    }
    return 0
}

# Verify that the data in table ${1} is correct
verifyTableData() {
    pattern="^[0-9]+,[^,]*,[-0-9\. \t]+,[^,]+,[-0-9 \t]+$"
    while read line; do
	[[ -z "${line}" || "${line}" =~ ${pattern} ]] || {
	    echo "Error parsing table from file ${1}" >&2
	    return 1
	}
    done < "${1}"
    return 0
}

# Prints the totals for a table file given in ${1}
tableTotals() {
    # Ensure table correct
    verifyTableData "${1}" || return 1

    # Check that desired fule exists
    [[ -f "${1}" ]] || return 1
    result=$(column -s',' -t -H1,2,4,5 "${1}" | paste -sd+ | bc)
    [[ -z "${result}" ]] && echo "0" || echo "${result}"
}

# STATISTICS FUNCTIONS

# Runs the stats commands given in ${1}
runStats() {

    # Supported Commands:
    #   - group <name | amount | tag | date>
    #   - ungroup
    #   - check <EXPR>
    #   - collapse <avg | min | max | sum | count>
    #   - select <name | amount | tag | date>

    # Split command string
    OIFS=${IFS}
    IFS=\;
    read -a commands <<< "${1}"
    IFS=${OIFS}

    # Move appropriate file into a temporary directory
    mkdir -p ./.stats_tmp
    cp "${TABLE_FILE}" ./.stats_tmp/
    pushd ./.stats_tmp > /dev/null

    # Iterate through command string
    for cmd in "${commands[@]}"; do
	# For each command, split by space, then process
	read -a args <<< ${cmd}
	case "${args[0]}" in
	    "group")
		num="$(sed -n -e "s/.*name.*/2/p" -e "s/.*amount.*/3/p" -e "s/.*tag.*/4/p" -e "s/.*date.*/5/p" <<< "${args[1]}")"
		[[ -z "${num}" ]] && echo "Stats error: incorrect argument for 'group': ${args[1]}" >&2 || {
		    for file in $(find . -name "*.csv"); do
			tableGroup "${file}" "${num}"
		    done
		}
	    ;;
	    "ungroup")
		for file in $(find . -name "*.csv"); do
		    folder="$(dirname ${file})"
		    [[ -d "${folder}" ]] && tableUngroup "${folder}"
		done
	    ;;
	    "check")
		for file in $(find . -name "*.csv"); do
		    checkArg="${args[@]:1}"
		    tableCheck "${file}" "${checkArg}"
		done
	    ;;
	    "collapse")
		for file in $(find . -name "*.csv"); do
		    tableCollapse "${file}" "${args[1]}"
		done
	    ;;
	    "select")
		nums="$(sed -e "s/name/2/" -e "s/amount/3/" -e "s/tag/4/" -e "s/date/5/" <<< "${args[1]}")"
		for file in $(find . -name "*.csv"); do
		    tableSelect "${file}" "${nums}"
		done
	    ;;
	    *)
		echo "Stats error: incorrect command ${args[0]}" >&2
	esac
    done

    cat ./*.csv
    popd > /dev/null
    rm -r ./.stats_tmp
}

# Split csv file given by ${1} into groups based on the column number given by ${2} and keep them in a directory ${1} (without extension)
tableGroup() {
    dirname="${1%.*}"
    mkdir -p "${dirname}"
    awk "BEGIN { FS=\",\"; OFS=\",\" } { if(NF == 5) { name = \$${2}; gsub(/ /, \"\", name); print \$0 >> \"${dirname}/\"name\".csv\"; } }" "${1}"
    rm "${1}"
}

# Join together csv files from folder ${1} into file '${1}.csv' which replaces the folder
tableUngroup() {
    cat ${1}/*.csv > "${1}.csv"
    rm -r "${1}"
}

# Check the table given by ${1}, only keep rows fitting the expression in ${2}
#  - valid expression format: 'name|amount|tag|date' '<|>|<=|>=|==|!=|~|!~|in'  'value'
tableCheck() {
    regex="(name|amount|tag|date)[ \\t]*(\\<|\\>|\\<=|\\>=|==|!=|~|!~|in)[ \\t]*[^;]+"
    [[ "${2}" =~ ${regex} ]] || {
	echo "Invalid stats expression to check: '${2}'" >&2
	return 1
    }
    expression="$(sed -e "s/^name/\$2/" -e "s/^amount/\$3/" -e "s/^tag/\$4/" -e "s/^date/\$5/" <<< "${2}")"
    fieldNum="$(sed -e "s/\([^ \t]\+\).*/\1/" <<< "${expression}")"
    awk "BEGIN { FS=\",\"; OFS=\",\" } { line=\$0; gsub(/ /, \"\", ${fieldNum}); if(${expression}) { print line } }" "${1}" > "${1}_"
    mv "${1}_" "${1}"
}

# Collapse the table given by ${1} by the function given in ${2} (can be <avg | min | max | sum | count>) on the 'amount' field
tableCollapse() {
    itCode=""
    endCode="print \"ERROR\""
    # Get appropriate commands based on input op
    case "${2}" in
	"avg")
	    itCode='sum += $3'
	    endCode='print sum/NR'
	;;
	"min")
	    itCode='if($3 < min) { min = $3 }'
	    endCode='print min'
	;;
	"max")
	    itCode='if($3 > max) { max = $3 }'
	    endCode='print max'
	;;
	"sum")
	    itCode='sum += $3'
	    endCode='print sum'
	;;
	"count")
	    itCode=''
	    endCode='print NR'
    esac
    result="$(awk -F, "{ ${itCode} } END { ${endCode} }" "${1}")"
    tags="$(awk -F, "{ arr[\$4] = \"\"; } END { for(i in arr) { printf i; }; print \"\" }" "${1}")"
    dates="$(awk -F, "{ arr[\$5] = \"\"; } END { for(i in arr) { printf i; }; print \"\" }" "${1}")"
    echo "0, table ${2}, ${result}, ${tags}, ${dates}" > "${1}"
}

# Select only the columns given in ${2} (comma-separated column number list) of the table given by ${1}
tableSelect() {
    awk -F, "BEGIN { split(\"${2}\", nums, \",\") } { for(i in nums) { if(i > 1) { printf \",\" }; printf \$nums[i] }; print \"\" }" "${1}" > "${1}_"
    mv "${1}_" "${1}"
}


# PROGRAM SECTION

[[ $# -gt 1 || "${1}" == "--help" || "${1}" == "-h" ]] && {
    programHelp
    exit 0;
}

# Program variables (environment-exportable configuration)
[[ -z "${ACC_FILE}" ]] && ACC_FILE="accounts.dat"
[[ -z "${TAG_FILE}" ]] && TAG_FILE="tags.dat"
[[ -z "${STATS_FILE}" ]] && STATS_FILE="stats.dat"

# Get project directory and verify permissions
DIR="${1}"
[[ -z ${DIR} ]] && DIR=".money_man_data"

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
#    - Statistics about spending for all account (breakdown by tag, average table entry, average daily entry/grouped by date, any unexpectedly big values)
#  - Add QOL features:
#    - Removing accounts, tags and tables
#    - Stats with no table selected runs stats for each table separately
#    - Table file validation at select to know if anything invalid
#    - Renaming tags, accounts and tables
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
	    echo ""
	    echo "Account Commands:"
	    echo " - acc ................................ shows existing accounts"
	    echo " - acc [account name] ................. sets the current account to be the given account name, if nonexistent, creates new account"
	    echo " - info ............................... shows information about the current account, including the starting and current balance"
	    echo " - log ................................ shows a table-wise account log, displaying all included tables and the balance after each"
	    echo " - balance [new starting balance] ..... shows info about the current balance, or sets the starting balance to the given value"
	    echo ""
	    echo "Table Commands:"
	    echo " - list ............................... lists tables in the account, typically this would be months"
	    echo " - select <table name> ................ selects the specified table from the account, if nonexistent, creates new table"
	    echo " - print [num lines] .................. prints num lines of content from the current table (or all tables if none selected), or all if blank or <0, sorted by date"
	    echo " - add <desc> <amount> <tag> <date> ... adds a line to the table with the given info, use quotes for spaces"
	    echo " - rm <id to remove> .................. removes the line with the specified ID"
	    echo ""
	    echo "Misc Commands:"
	    echo " - tag ................................ shows existing tags available for entries"
	    echo " - tag [tag name] ..................... shows details about existing tag or creates new if nonexistent"
	    echo " - export [file name] ................. exports the current table from the current account into a file with the given name"
	    echo " - import <csv name> .................. imports the rows from the given CSV file (if compatible) into the current table in the current account"
	    echo " - unselect <table|acc> ............... sets the current table or account to NONE"
	    echo ""
	    echo "Stats Commands:"
	    echo " - stats <function name> .............. runs the given statistics function on the currently selected table and prints results"
	    echo " - stats list ......................... shows existing statistics functions (name -> code)"
	    echo " - stats add .......................... prompts the user to add a new statistics function, or update an already existing one with new code"
	    echo " - stats del .......................... prompts the user for a name of a statistics function to delete"
	    echo ""
	    echo "Stats Function Language Commands:"
	    echo " - group <name|amount|tag|date> ....... groups the selected table into subtables based on the given column"
	    echo " - ungroup ............................ joins the last grouped subtables together"
	    echo " - check <EXPR> ....................... evaluates a logic expression (containing name|amount|tag|date left-hand side names) and keeps only true rows"
	    echo " - collapse <avg|min|max|sum|count> ... collapses all rows by the amount column using the given function"
	    echo " - select <name,amount,tag,date> ...... keeps only the columns provided in a comma-separated list of the given options"
	    echo " - NOTE: All commands except for ungroup operate on either the selected table, or on all subtables separately if subtables exist"

	;;

	acc)
	    # Setup accounts file if nonexistent
	    [[ -e "${ACC_FILE}" ]] || {
		touch "${ACC_FILE}" || {
		    # Error reporting if file can't be created
		    echo "Error: Could not create Accounts file and none exists" >&2
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
		# Check if account data file exists, create if not
		[[ -f "./${ACC}.dat" ]] || {
		    echo "0" > "./${ACC}.dat"
		}

		# Reset selected table
		TABLE="none"
		TABLE_FILE=
	    } || {
		# Display all existing accounts
		echo "Existing Accounts:"
		cat "${ACC_FILE}"
	    }
	;;

	info)
	    verifyAcc || continue

	    # Get current balance
	    balance=$(cat "./${ACC}.dat")

	    # Get balance for each table in the account
	    tableBalance=0
	    for file in $(find . -name "${ACC}-*"); do
		fileBalance=$(tableTotals "${file}") && tableBalance=$(echo "$tableBalance + $fileBalance" | bc)
	    done
	    # Get final balance
	    finalBalance=$(echo "$balance + $tableBalance" | bc)

	    # Print account details
	    echo "Account ${ACC}:"
	    echo " - Starting balance: ${balance}"
	    echo " - Final balance: ${finalBalance}"
	;;

	log)
	    verifyAcc || continue

	    # Get current balance
	    balance=$(cat "./${ACC}.dat")

	    # Print start info
	    echo "Account ${ACC} table log:"
	    echo "Starting balance: ${balance}"

	    # Go through each file, extract file totals, write details
	    for file in $(find . -name "${ACC}-*" | sort); do
		fileBalance=$(tableTotals "${file}") && balance=$(echo "$balance + $fileBalance" | bc)
		echo "---"
		echo "Table $(echo ${file} | sed "s/\.\/${ACC}-\(.*\)\.csv/\1/"):"
		echo " - Table final balance: ${fileBalance}"
		echo " - Account final balance: ${balance}"
	    done
	    echo "---"
	;;

	balance)
	    verifyAcc || continue

	    [[ ${#parsed[@]} -gt 1 ]] && {
		# Changing starting account balance
		echo "${parsed[1]}" > "${ACC}.dat"
		echo "Updated account ${ACC} starting balance to ${parsed[1]}"
	    } || {
		# Displaying account balance
		echo "Account ${ACC} starting balance: $(cat ${ACC}.dat)"
	    }
	;;

	list)
	    # If account selected, list all tables in account
	    verifyAcc || continue
	    find . -name "${ACC}-*" | sed "s/\.\/${ACC}-\(.*\)\.csv/\1/" | sort
	;;

	select)
	    # If specified and exists, selects the desired table in the current account
	    [[ ${#parsed[@]} -lt 2 ]] && {
		echo "Please provide table to select" >&2
		continue
	    }
	    verifyAcc || continue

	    # Selecting desired table and checking if present
	    tableFile="./${ACC}-${parsed[1]}.csv"
	    [[ -e "${tableFile}" ]] || {
		read -p "Table '${parsed[1]}' not found. Create? (y/n) "
		[[ "$REPLY" == "y"* || "$REPLY" == "Y"* ]] && {
		    touch "${tableFile}"
		    echo "Created table ${parsed[1]}"
		} || {
		    echo "Cancelled"
		    continue
		}
	    }
	    TABLE="${parsed[1]}"
	    TABLE_FILE="${tableFile}"
	;;

	print)
	    # Check if table selected, otherwise print all
	    verifyTable && {
		# Print N lines
		[[ -z "${parsed[1]}" ]] && {
		    sort -k5 -t"," "${TABLE_FILE}" | column -s"," -N"ID,Description,Amount,Tag,Date" -o" | " -t
		} || {
		    sort -k5 -t"," "${TABLE_FILE}" | column -s"," -N"ID,Description,Amount,Tag,Date" -o" | " -t | head -n $((${parsed[1]}+1))
		}
	    } || {
		for file in $(find . -name "${ACC}-*" | sort); do
		    echo "PRINTING TABLE $(echo ${file} | sed "s/\.\/${ACC}-\(.*\)\.csv/\1/"):"
		    [[ -z "${parsed[1]}" ]] && {
			sort -k5 -t"," "${file}" | column -s"," -N"ID,Description,Amount,Tag,Date" -o" | " -t
		    } || {
			sort -k5 -t"," "${file}" | column -s"," -N"ID,Description,Amount,Tag,Date" -o" | " -t | head -n $((${parsed[1]}+1))
		    }
		    echo "---"
		done
	    }
	;;

	add)
	    # Validate add command
	    verifyTable || continue
	    [[ ${#parsed[@]} -ne 5 ]] && {
		echo "Please use specified add format: 'add <desc> <amount> <tag> <date>'" >&2
		continue
	    }

	    # Validate if tag exists
	    grep -q "^${parsed[3]}$" "${TAG_FILE}" || {
		echo "Tag ${parsed[3]} not found. See existing tags using 'tag' or create a new one using 'tag [name]'" >&2
		continue
	    }

	    # Get last line ID
	    lastID=$(sort -k1rn "${TABLE_FILE}" | head -n1 | sed -ne "s/^\([0-9]\+\),.*/\1/p")
	    ID=$((${lastID} + 1))
	    # Add line
	    echo "${ID}, ${parsed[1]}, ${parsed[2]}, ${parsed[3]}, ${parsed[4]}" >> "${TABLE_FILE}"
	;;

	rm)
	    # Validate rm command
	    verifyTable || continue
	    [[ ${#parsed[@]} -ne 2 ]] && {
		echo "Please use specified rm format: 'rm <id to remove>'" >&2
		continue
	    }
	    grep -q "^${parsed[1]}," "${TABLE_FILE}" || {
		echo "ID ${parsed[1]} not found in table ${TABLE}" >&2
		continue
	    }
	    
	    # Remove record from table file
	    sed -e "/^${parsed[1]},/d" -i "${TABLE_FILE}"
	;;

	tag)
	    # Setup tags file if nonexistent
	    [[ -e "${TAG_FILE}" ]] || {
		touch "${TAG_FILE}" || {
		    # Error reporting if file can't be created
		    echo "Error: Could not create Tags file and none exists" >&2
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

	stats)

	    # Set up stats commands file if not found
	    [[ -e "${STATS_FILE}" ]] || {
		touch "${STATS_FILE}" || {
		    echo "Error: Could not create Stats functions file and none exists" >&2
		    continue
		}
	    }

	    # Check that argument present
	    [[ -z "${parsed[1]}" ]] && {
		echo "Error: 'stats' needs one argument" >&2
		continue
	    }

	    # Parsing arguments
	    case "${parsed[1]}" in
		"list")
		    sed -e "s/\(^[^;]\+\);\(.*\)/\1 -> \2/" "${STATS_FILE}"
		;;
		"del")
		    read -p "Which stats function to delete: " delName
		    grep "^${delName};" "${STATS_FILE}" > /dev/null && {
			sed -i -e "/^${delName};/d" "${STATS_FILE}"
		    } || {
			echo "Error: Can't delete stats function ${delName} as it doesn't exist" >&2
		    }
		;;
		"add")
		    read -p "Enter (unique) name of the stats function to add: " addName
		    read -p "Enter stats function code: " addCode
		    # Updating stats function if exists, otherwise appending new
		    grep "^${addName};" "${STATS_FILE}" > /dev/null && {
			sed -i -e "s/^\(${addName}\);.*/\1; ${addCode}/" "${STATS_FILE}"
		    } || {
			echo "${addName}; ${addCode}" >> "${STATS_FILE}"
		    }
		;;
		*)
		    # Before running stats functions, check that table selected
		    verifyTable || continue

		    # Run the actual stats function if found in the stats file
		    grep "^${parsed[1]};" "${STATS_FILE}" > /dev/null && {
			cmd="$(sed -ne "s/^${parsed[1]};\(.*\)/\1/p" "${STATS_FILE}")"
			echo "Stats function: ${parsed[1]}"
			runStats "${cmd}"
		    } || {
			echo "Error: Stats function '${parsed[1]}' not found (add using 'stats add')" >&2
		    }
	    esac
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

	unselect)
	    [[ "${parsed[1]}" == "acc" ]] && {
		echo "Unselected account"
		ACC="none"
		TABLE="none"
	    } || {
		[[ "${parsed[1]}" == "table" ]] && {
		    echo "Unselected table"
		    TABLE="none"
		} || {
		    echo "Please specify 'table' or 'acc' as the first argument"
		    continue
		}
	    }
	;;

	*)
	    echo "Error: Command '${cmd}' not recognized. Try help" >&2
    esac

    # Clearing line for the next read call
    LINE=

done

