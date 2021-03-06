package require Tcl 8.5

package require toclbox::common

namespace eval ::toclbox::log {
    namespace eval hijack {};   # Will contain hijacked logger relay procedures
    namespace eval vars {
        variable -tags    {1 CRITICAL 2 ERROR 3 WARN 4 NOTICE 5 INFO 6 DEBUG 7 TRACE}
        variable -header  "\[%Y%m%d %H%M%S\] \[%lvl%\] \[%pkg%\] "
        variable -verbose {* 5}
        variable dbgfd    stderr
        variable unknown  --U-N-K-N-O-W-N--
        variable version  [lindex [split [file rootname [file tail [info script]]] -] end]
        variable ignore   [list]
    }
    namespace export {[a-z]*}
    namespace ensemble create -command ::tocllog
    namespace import [namespace parent]::common::mapper [namespace parent]::common::fullpath
}


# ::toclbox::log::format -- Format log line
#
#      Format a log entry to a line using the current specified header, which
#      includes formatting the data and time passed as an argument. When the
#      date/time is emoty, this will be considered as "now", i.e. the current
#      date and time at the host.
#
# Arguments:
#      lvl      Level of the log entry
#      pkg      Name of the package at which the entry is happening
#      output   Message
#      now      Number of seconds since the epoch for the entry, empty for now
#
# Results:
#      Formatted log entry, ready for output
#
# Side Effects:
#      None.
proc ::toclbox::log::format { lvl pkg output {now ""}} {
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
    if { $now eq "" } {
        set now [clock seconds]
    }
    set hdr [clock format $now -format $hdr]
    
    # Concat and return
    return ${hdr}${output}
}


# ::toclbox::log::silencer -- Silences log lines
#
#      Register patterns matching lines and/or packages that will be silenced
#      from the log output. In most cases, this is not a good idea, but the
#      feature can be used to removed annoying repeating messages that are known
#      to occur in a given context.
#
# Arguments:
#      ptn      Pattern matching the line
#      pkg      Pattern matchint the package name (defaults to all, e.g. *)
#
# Results:
#      None.
#
# Side Effects:
#      Matching lines from matching packages will be ignored from now on.
proc ::toclbox::log::silencer { ptn { pkg * } } {
    lappend vars::ignore $pkg $ptn
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
            if {[Level $verbosity] >= $lvl && ![Ignore? $output $pkg] } {
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


# ::toclbox::log::hijack -- Hijack logger output
#
#       This procedure hijacks the tcllib logger module in the sense that it
#       arranges for all services that are declared within the logger module (if
#       present and required) to be passed through the services of this module
#       instead. Debugging levels are automatically translated.
#
# Arguments:
#       None.
#
# Results:
#       Returns the list of logger services that were hijacked properly
#
# Side Effects:
#       This creates as many procedures as necessary under a children namespace
#       to relay between the logger output procedure facility and the debug
#       command.
proc ::toclbox::log::hijack {} {
    set hijacked [list]
    if { [catch {logger::services} services] == 0 } {
        foreach s $services {
            if { [string first ":" $s] >= 0 } {
                debug WARN "Cannot hijack namespaced services!"
            } else {
                set log [logger::servicecmd $s]
                foreach l [logger::levels] {
                    # The logger module is only able to work with procedures
                    # (NOT commands) when registering commands for performing
                    # the logging. So we create a procedure for each level and
                    # service under a children namespace and register that
                    # procedure as the logging procedure. We arrange for the
                    # name of the procedure to reflect the service and level.
                    proc [namespace current]::hijack::${l}_$s {txt} {
                        # Re-extract the log level and service out of the name
                        # of the procedure
                        set procname [lindex [info level 0] 0]
                        set spec [lindex [split $procname :] end]
                        set underscore [string first "_" $spec]
                        set lvl [string range $spec 0 [expr {$underscore-1}]]
                        set service [string range $spec [expr {$underscore+1}] end]
                        # Convert between logging levels of the two modules.
                        set l [string map [list debug DEBUG \
                                info INFO \
                                notice NOTICE \
                                warn WARN \
                                error ERROR \
                                critical CRITICAL \
                                alert CRITICAL \
                                emergency CRITICAL] [string tolower $lvl]]
                        # Should we uplevel here?
                        [namespace parent]::debug $l $txt $service
                    }
                    
                    ${log}::logproc $l [namespace current]::hijack::${l}_$s
                }
                lappend hijacked $s
            }
        }
    } else {
        debug WARN "Cannot hijack tcllib logger module, make sure package is present!"
    }
    
    return $hijacked
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


# ::toclbox::log::Ignore? -- Ignore log entry?
#
#      Should a given log entry be ignored?
#
# Arguments:
#      output   Current message in entry
#      pkg      Name of package where the message originates from
#
# Results:
#      1 if the entry should be silenced and ignored, 0 otherwise.
#
# Side Effects:
#      None.
proc ::toclbox::log::Ignore? { output pkg } {
    foreach { pkg_ptn msg_ptn } $vars::ignore {
        if { [string match $pkg_ptn $pkg] && [string match $msg_ptn $output] } {
            return 1
        }
    }
    return 0
}

package provide toclbox::log $::toclbox::log::vars::version


