package require Tcl 8.5

package require toclbox::common

namespace eval ::toclbox::log {
    namespace eval vars {
	variable -tags    {1 CRITICAL 2 ERROR 3 WARN 4 NOTICE 5 INFO 6 DEBUG 7 TRACE}
	variable -header  "\[%Y%m%d %H%M%S\] \[%lvl%\] \[%pkg%\] "
	variable -verbose {* 5}
	variable dbgfd    stderr
        variable unknown  --U-N-K-N-O-W-N--
    }
    namespace export {[a-z]*}
    namespace ensemble create -command ::tocllog
    namespace import [namespace parent]::common::mapper [namespace parent]::common::fullpath
}


proc ::toclbox::log::format { lvl pkg output } {
    # Convert to integer
    set lvl [Level $lvl]
    # Convert to existing and known human-readable level if possible.
    if { [dict exists ${vars::-tags} $lvl] } {
        set lvl [dict get ${vars::-tags} $lvl]
    } else {
        set lvl $vars::unknown
    }
    # Convert to lowercase.
    set lvl [string tolower $lvl]
    # Map known dynamic variables
    set hdr [string map [mapper "" pkg $pkg lvl $lvl] ${vars::-header}]
    # Relay clock formatting routines.
    set hdr [clock format [clock seconds] -format $hdr]
    
    # Concat and return
    return ${hdr}${output}
}


# ::utils::debug -- Conditional debug output
#
#       Output debug message depending on the debug level that is
#       currently associated to the library.  Debug occurs on the
#       registered file descriptor.
#
# Arguments:
#	lvl	Debug level of message, lib. level must be lower for input
#	output	Message to write out, possibly
#
# Results:
#       None.
#
# Side Effects:
#       Write message onto debug file descriptor, if applicable.
proc ::toclbox::log::debug { lvl output { pkg "" } } {
    set lvl [Level $lvl]

    if { $pkg eq "" } {
	set pkg [lindex [split [string trim [uplevel 1 namespace current] ":"] ":"] end]
	if { $pkg eq "" } {
	    set pkg [file rootname [file tail [fullpath]]]
	}
    }

    foreach { ptn verbosity } ${vars::-verbose} {
	if { [string match $ptn $pkg] } {
	    if {[Level $verbosity] >= $lvl } {
		if { [string index $vars::dbgfd 0] eq "@" } {
		    set cmd [string range $vars::dbgfd 1 end]
		    if { [catch {eval [linsert $cmd end $lvl $pkg $output]} err] } {
			puts stderr "Cannot callback external log command: $err"
		    }
		} else {
		    set line [format $lvl $pkg $output]
		    if { $line ne "" } {
			puts $vars::dbgfd $line
		    }
		}
	    }
	    return
	}
    }
}


# ::utils::logger -- Arrange to output log to file (descriptor)
#
#       This procedure will send the output log to a file.  If it is
#       called with the path to a file, the file will be appended for
#       log output.  Otherwise the argument is understood as being an
#       already opened file descriptor.  Existing logging to another
#       log file will be cancelled before new logging is setup.
#
# Arguments:
#	fd	File descriptor, path to file or command
#
# Results:
#       Returns the file descriptor used for logging.
#
# Side Effects:
#       None.
proc ::toclbox::log::logger { { fd_or_n "" } } {
    if { $fd_or_n ne "" } {
	if { [string index $fd_or_n 0] eq "@" } {
	    set fd $fd_or_n
	} else {
	    # Open file for appending if it is a file, otherwise consider the
	    # argument as a file descriptor.
	    if { [catch {fconfigure $fd_or_n}] } {
		debug 3 "Appending log to $fd_or_n"
		if { [catch {open $fd_or_n a} fd] } {
		    debug 2 "Could not open $fd_or_n: $fd"
		    return -code error "Could not open $fd_or_n: $fd"
		}
	    } else {
		set fd $fd_or_n
	    }
	}
    
	# Close previous debug file descriptor if it was not a standard
	# one and setup new one.
	if { ![string match std* $vars::dbgfd] } {
	    catch {close $vars::dbgfd}
	}
	if { [string index $fd 0] ne "@" } {
	    fconfigure $fd -buffering line
	}
	set vars::dbgfd $fd
	debug 3 "Log output successfully changed to new target"        
    }

    return $vars::dbgfd
}


# ::utils::verbosity -- Set module verbosity
#
#       Change the verbosity for modules. This procedure should take
#       an even-long list, where each odd argument is a pattern (to be
#       matched against the name of the existing logging modules) and
#       even arguments is the log level for the matching module(s).
#
# Arguments:
#	args	Even-long list of verbosity specification for modules.
#
# Results:
#       Return old verbosity levels
#
# Side Effects:
#       None.
proc ::toclbox::log::verbosity { args } {
    set old ${vars::-verbose}
    set vars::-verbose {}
    foreach { spec lvl } $args {
	set lvl [Level $lvl]
	if { [string is integer $lvl] && $lvl >= 0 } {
	    lappend vars::-verbose $spec $lvl
	}
    }
    
    if { $old ne ${vars::-verbose} } {
	debug 4 "Changed module verbosity to: ${vars::-verbose}"
    }

    return $old
}


# ::utils::LogLevel -- Convert log levels
#
#       For convenience, log levels can also be expressed using
#       human-readable strings.  This procedure will convert from this
#       format to the internal integer format.
#
# Arguments:
#	lvl	Log level (integer or string).
#
# Results:
#       Log level in integer format, -1 if it could not be converted.
#
# Side Effects:
#       None.
proc ::toclbox::log::Level { lvl } {
    if { ![string is integer $lvl] } {
	foreach {l str} ${vars::-tags} {
	    if { [string match -nocase $str $lvl] } {
		return $l
	    }
	}
	return -1
    }
    return $lvl
}




package provide toclbox::log 1.0