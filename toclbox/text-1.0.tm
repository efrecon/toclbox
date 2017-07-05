package require Tcl 8.5

package require toclbox::common
package require toclbox::log
package require toclbox::config

namespace eval ::toclbox::text {
    namespace eval vars {
	variable -resolve     10
	variable -separator   {/ |}
        variable -ellipsis    "(..)"
		variable -offload     "@"
    }
    namespace export {[a-z]*}
    namespace import [namespace parent]::log::debug
    namespace import [namespace parent]::common::mapper \
			[namespace parent]::common::fullpath \
			[namespace parent]::common::defaults
    namespace ensemble create -command ::tocltxt
}

# ::utils::resolve -- Resolve %-sugared string in text
#
#       This procedure will resolve the content of "variables" (see
#       next), enclosed by %-signs to their content.  By default, the
#       variables recognised are all the keys of the tcl_platform
#       array, all environment variables and prgdir and prgname, which
#       are resolved from the full normalized path to the program.
#       The procedure also takes an additional even-long list of
#       variables that can occur as part of this resolution.  If the
#       value of a variable contains itself %-enclosed variables,
#       these will also be resolved.  The procedure guarantee a finite
#       number of iterations to avoid infinite loops.
#
# Arguments:
#	txt	Text to be resolved
#	keys	Additional even-long list of vars and values.
#
# Results:
#       The resolved string, after a finite number of iterations.
#
# Side Effects:
#       None.
proc ::toclbox::text::resolve { txt { keys {} } } {
    # Generate a mapper that we will be able to quickly resolve
    # non-defaulting expressions with.
    set keys [Keys $keys]
    set mapper {}
    foreach {k v} $keys {
	mapper mapper $k $v
    }
    
    # Recursively map, meaning that we can use the content of keys in
    # keys...
    for { set i 0 } { $i < ${vars::-resolve} } { incr i } {
	set rtxt [string map $mapper $txt]
	if { $rtxt eq $txt } {
	    return [Defaults $rtxt $keys]
	}
	set txt $rtxt
    }

    debug ERROR "Maximum number of resolution iterations reached!"
    return [Defaults $txt $keys]
}

proc ::toclbox::text::offload { varname {divider -1} {type "file"} {keys {}} } {
	upvar $varname var
	if { [string first ${vars::-offload} $var] == 0 } {
		set fname [string trim [string range $var [string length ${vars::-offload}] end]]
		set fname [resolve $fname $keys]
		set var [[namespace parent]::config::read $fname $divider $type]
		return $fname
	}
	return ""
}


proc ::toclbox::text::Keys { {keys {}} } {
    global env tcl_platform
    
    set mapper {}
    foreach {k v} [array get tcl_platform] {
	lappend mapper $k $v
    }
    foreach {k v} [array get env] {
	lappend mapper $k $v
    }
    foreach {k v} $keys {
	if { [string trim $k] ne "" && [string trim $v] ne "" } {
	    lappend mapper $k $v
	}
    }
    set fullpath [fullpath]
    lappend mapper progdir [file dirname $fullpath]
    lappend mapper prgdir [file dirname $fullpath]
    lappend mapper progname [file rootname [file tail $fullpath]]
    lappend mapper prgname [file rootname [file tail $fullpath]]

    return $mapper
}


# Kept for posterity, but this implementation does not work (even though it is
# believed to be quicker)
proc ::toclbox::text::Defaults { txt {keys {}}} {
    array set CURRENT $keys
    foreach s [defaults [namespace parent]::common -subst] {
	foreach separator ${vars::-separator} {
	    # Generate a regular expression that will match strings
	    # enclosed by the substitutions characters with one of the
	    # defaulting separators.  We backslash the parenthesis to
	    # avoid them as being understood as indices in arrays.  We
	    # backslash the separator to make sure we match on the
	    # character and nothing else.  We group to easily find out
	    # the default value below.
	    set rx "${s}\(.*?\)\\${separator}\(.*?\)${s}"
	    
	    if { [llength [::split $txt $separator]] >= 2 } {
		# Replace all occurences of what looks like defaulting
		# instructions to the default that they contain.
		while 1 {
		    # Find next match in string and break out of loop if
		    # none found.
		    set match [regexp -all -inline -indices -- $rx $txt]
		    if { [llength $match] == 0 } {
			break
		    }
		    # Access the match, all these will be pairs of
		    # indices.
		    foreach {m v dft} $match break
		    # Extract the (default) value from the string and
		    # relace the whole defaulting construct with the
		    # default value or the value of the key
		    set k [string range $txt [lindex $v 0] [lindex $v 1]]
		    if { [info exists CURRENT($k)] } {
			set val $CURRENT($k)
		    } else {
			set val [string range $txt [lindex $dft 0] [lindex $dft 1]]
		    }
		    set txt [string replace $txt [lindex $m 0] [lindex $m 1] $val]
		}
	    }
	}
    }
    return $txt
}


proc ::toclbox::text::Defaults { txt {keys {}}} {
    array set CURRENT $keys
    foreach s [defaults [namespace parent]::common -subst] {
        set start 0
        while {1} {
            # Look for next occurrence of the substitution marker
            set start [string first $s $txt $start]
            if { $start < 0 } {
                break;     # Not found, we are done for this time.
            }
            
            # Look for the ending marker.
            set end [string first $s $txt [expr {$start + 1}]]
            if { $end < 0 } {
                break;  # Not found, we are done for this time (but this is a bit
                        # suspect.)
            }
            
            set order [list]
            foreach sep ${vars::-separator} {
                set idx [string first $sep $txt [expr {$start + 1}]]
                if { $idx >= 0 && $idx < $end } {
                    lappend order [list $sep $idx]
                }
            }
            
            if { [llength $order] } {
                # Arrange for sep and idx to contain the separator and the index
                # that are closest from the start
                lassign [lindex [lsort -index 1 -increasing -integer $order] 0] sep idx
                set k [string range $txt [expr {$start+1}] [expr {$idx-1}]]
                if { [lsearch $keys $k] >= 0 } {
                    set txt [string replace $txt $start $end $CURRENT($k)]
                } else {
                    set dft [string range $txt [expr {$idx+1}] [expr {$end-1}]]
                    set txt [string replace $txt $start $end $dft]
                }
            } else {
                set k [string range $txt [expr {$start+1}] [expr {$end-1}]]
                if { [lsearch $keys $k] >= 0 } {
                    set txt [string replace $txt $start $end $CURRENT($k)]
                } else {
                    set start $end;   # Couldn't find anything, jump to next
                }
            }
            
        }
    }
    
    return $txt
}


proc ::toclbox::text::sed {script input} {
    set sep [string index $script 1]
    foreach {cmd from to flag} [::split $script $sep] break
    switch -- $cmd {
	"s" {
	    set cmd regsub
	    if {[string first "g" $flag]>=0} {
		lappend cmd -all
	    }
	    if {[string first "i" [string tolower $flag]]>=0} {
		lappend cmd -nocase
	    }
	    set idx [regsub -all -- {[a-zA-Z]} $flag ""]
	    if { [string is integer -strict $idx] } {
		set cmd [lreplace $cmd 0 0 regexp]
		lappend cmd -inline -indices -all -- $from $input
		set res [eval $cmd]
		set which [lindex $res $idx]
		return [string replace $input [lindex $which 0] [lindex $which 1] $to]
	    }
	    # Most generic case
	    lappend cmd -- $from $input $to
	    return [eval $cmd]
	}
	"e" {
	    set cmd regexp
	    if { $to eq "" } { set to 0 }
	    if {![string is integer -strict $to]} {
		return -error code "No proper group identifier specified for extraction"
	    }
	    lappend cmd -inline -- $from $input
	    return [lindex [eval $cmd] $to]
	}
	"y" {
	    return [string map [list $from $to] $input]
	}
    }
    return -code error "not yet implemented"
}

# ::biot::common::psplit -- Protected split
#
#       This is a re-implementation of the split command, but also
#       supporting protection of characters.  Characters preceeded by
#       the protecting char will not be considered as split
#       separators.
#
# Arguments:
#	str	Strint to split
#	seps	Separators to use for split
#	protect	Protecting character to avoid splitting on next char.
#
# Results:
#       The list of separated tokens
#
# Side Effects:
#       None.
proc ::toclbox::text::split { str seps {protect "\\"}} {
    # Fix special cases of empty string and empty separators.
    if { $str eq "" } {
        return $str
    }
    if { $seps eq "" } {
        return [::split $str ""]
    }
    
    set out [list]
    set prev ""
    set current ""
    foreach c [::split $str ""] {
	if { [string first $c $seps] >= 0 } {
	    if { $prev eq $protect } {
		set current [string range $current 0 end-1]
		append current $c
	    } else {
		lappend out $current
		set current ""
	    }
	    set prev ""
	} else {
	    append current $c
	    set prev $c
	}
    }
    
    lappend out $current

    return $out
}


proc ::toclbox::text::human { val {max 20} } {
    set ellipsis ""
    if { $max > 0 } {
	if { [string length $val] > $max } {
	    set val [string range $val 0 [expr {$max-1}]]
	    set ellipsis ${vars::-ellipsis}
	}
    }
    
    if { [string is print $val] } {
	return ${val}${ellipsis}
    } else {
	set hex ""
        foreach c [::split $val ""] {
            if { [string is print $c] } {
                append hex $c
            } else {
                append hex .
            }
        }
        append hex " (hex:"
	foreach c [::split $val ""] {
	    binary scan $c c1 num
	    set num [expr { $num & 0xff }]
	    append hex [format " %.2X" $num]
	}
        append hex ")"
	return ${hex}${ellipsis}
    }
    
    return ""
}


package provide toclbox::text 1.0
