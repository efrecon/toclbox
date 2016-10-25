package require Tcl 8.5

package require toclbox::log

namespace eval ::toclbox::config {
    namespace eval vars {
        variable -comments  "\#"
	variable -empty     {\"\" \{\} -}
    }
    namespace export {[a-z]*}
    namespace import [namespace parent]::log::debug
    namespace ensemble create -command ::toclcfg
}

proc ::toclbox::config::clean { lst } {
    set vals [list]
    foreach e $lst {
	set line [string trim $e]
	if { $line ne "" } {
	    set firstchar [string index $line 0]
	    if { [string first $firstchar ${vars::-comments}] < 0 } {
		# Allow to add empty values
		if { [lsearch -exact ${vars::-empty} $line] >= 0 } {
		    lappend vals ""
		} else {
		    if { [string index $line 0] eq "\"" \
			     && [string index $line end] eq "\"" } {
			lappend vals [string trim $line \"]
		    } else {
			lappend vals $line
		    }
		}
	    }
	}
    }
    return $vals
}


proc ::toclbox::config::scan { data { divider -1 } { type "data" } } {
    set data [string map [list "\r\n" "\n" "\r" "\n"] $data]
    return [LKeep [clean [split $data "\n"]] $divider $type]
}


# ::utils::lread -- Read lists from file
#
#       This is a generic "list reading" procedure that will read the
#       content of files where each line represents one element of a
#       list.  The procedure will gracefully ignore comments and empty
#       lines, thus providing a raw mechanism for reading
#       configurations files in a number of cases.  The procedure is
#       also able to count and control the number of elements in the
#       list that is read, forcing them to be a multiplier of xx and
#       cutting away the last elements not following the rule if
#       necessary.  This makes it perfect for parsing the result of
#       file reading using a foreach command.
#
# Arguments:
#	fname	Path to file to read
#	divider	Multiplier for number of elements, negative or zero to turn off
#	type	Type of file being read, used for logging output only.
#
# Results:
#       Return the elements contained in the file as a list.  If the
#       number of elements in the list had to be a multiplier of xx,
#       ending elements that do not follow the rule (if any) are
#       removed.  The list is empty on errors (or when no elements
#       were contained in the file.
#
# Side Effects:
#       None.
proc ::toclbox::config::read { fname { divider -1 } { type "file" } } {
    set vals [list]
    debug 4 "Reading $type from $fname"
    if { [catch {open $fname} fd] } {
	debug 2 "Could not read $type from $fname: $fd"
    } else {
	while { ! [eof $fd] } {
	    lappend vals [gets $fd]
	}
	close $fd
	set vals [LKeep [clean $vals] $divider "$type $fname"]
    }

    return $vals
}


proc ::toclbox::config::LKeep { vals dividers type } {
    set len [llength $vals]
    
    set exacts [list]
    set cuts [list]
    foreach divider $dividers {
	if { $divider > 0 } {
	    if { [expr {$len % $divider}] == 0 } {
		lappend exacts $divider
	    }
	    lappend cuts $divider
	}
    }
    
    if { [llength $cuts] > 0 } {
	if { [llength $exacts] > 0 } {
	    debug 5 "Acquired $len elements from $type"
	} else {
	    set keep [expr {($len / [lindex $exacts end])*[lindex $exacts end]}]
	    debug 3 "$type contained $len elements,\
		     wrong numer! Keeping $keep first ones"
	    set vals [lrange $vals 0 [expr {$keep - 1}]]
	}
    } else {
	debug 5 "Acquired $len elements from $type"
    }

    return $vals
}


package provide toclbox::config 1.0