package require Tcl 8.5

package require toclbox::common
package require toclbox::control
package require toclbox::log
package require toclbox::options
package require toclbox::island

namespace eval ::toclbox::templater {
    namespace eval templater {};    # Will host all templaters
    namespace eval vars {
        variable -var          "__r_e_s_u_l_t__"
        variable -munge        on
        variable -sourceCmd    ""
        variable -access       {}
        variable version       [lindex [split [file rootname [file tail [info script]]] -] end]
    }
    namespace export {[a-z]*}
    namespace import [namespace parent]::log::debug
    namespace import [namespace parent]::common::mapper \
            [namespace parent]::common::fullpath \
            [namespace parent]::common::defaults \
            [namespace parent]::control::identifier
    namespace ensemble create -command ::tocltpl
}


proc ::toclbox::templater::Source { t fname } {
    if { [set ${t}::-sourceCmd] eq "" } {
        debug 3 "Sourcing of external script $fname is forbidden\
                 unless you explicitely provide a callback"
    } else {
        if { [catch {eval [linsert [set ${t}::-sourceCmd] end \
                            $t $fname]} res] == 0 } {
            if { $res ne "" } {
                if { [catch {[set ${t}::interp] eval $res} err] } {
                    debug 3 "Sourcing of $fname failed: $err"
                }
            }
        } else {
            debug 3 "Inlining of $fname failed: $res"
        }
    }
}


proc ::toclbox::templater::PutS { args } {
    debug 5 [lindex $args end]
}


proc ::toclbox::templater::Append { t code_ out } {
    upvar $code_ code
    set var [set ${t}::-var]
    if { [string is true [set ${t}::-munge]] } {
        if { [string trim $out] ne "" || [string index $out end] ne "\n" } {
            append code "append $var [list $out]\n"
        }
    } else {
        append code "append $var [list $out]\n"
    }
}

proc ::toclbox::templater::Transcode { t txt } {
    set var [set ${t}::-var]
    set code "set $var {}\n"
    while {[set i [string first <% $txt]] != -1} {
        incr i -1
        Append $t code [string range $txt 0 $i]
        set txt [string range $txt [expr {$i + 3}] end]
        if {[string index $txt 0] eq "="} {
            append code "append $var "
            set txt [string range $txt 1 end]
        }
        if {[set i [string first %> $txt]] == -1} {
            return -code error "No matching %> when parsing\
                                '[string range $txt 0 15]...'"
        }
        incr i -1
        append code "[string range $txt 0 $i] \n"
        set txt [string range $txt [expr {$i + 3}] end]
    }
    if {$txt ne ""} { Append $t code $txt }
    append code "set $var"
    
    return $code
}



proc ::toclbox::templater::Init { t { force off } } {
    set itrp [set ${t}::interp]
    if { $itrp eq "" } {
        set ${t}::interp [interp create -safe -- \
                                [identifier [namespace current]::Interp]]
        set itrp [set ${t}::interp]
        $itrp alias puts [namespace code PutS]
        $itrp alias source [namespace code [list Source $t]]
        set ${t}::initvars [$itrp eval info vars]
    }
    
    # Give access to selected parts of the filesystem
    ::toclbox::island::reset $itrp
    foreach path [set ${t}::-access] {
        ::toclbox::island::add $itrp $path
    }
    
    if { [string is true $force] } {
        set vars [$itrp eval info vars]
        foreach v $vars {
            if { [lsearch [set ${t}::initvars] $v] < 0 } {
                $itrp eval unset $v
            }
        }
        set ${t}::code ""
    }
    
    return $itrp
}


proc ::toclbox::templater::alias { t src tgt args } {
    if { [set ${t}::interp] ne "" } {
        return [eval [set ${t}::interp] alias $src $tgt $args]
    }
}


proc ::toclbox::templater::setvar { t var args } {
    if { [llength $args] } {
        set value [lindex $args 0]
        debug 5 "Setting $var to be $value"
        return [[set ${t}::interp] eval [list set $var $value]]
    } else {
        return [getvar $t $var]
    }
}


proc ::toclbox::templater::getvar { t var } {
    return [[set ${t}::interp] eval [list set $var]]
}


proc ::toclbox::templater::render { t } {
    set txt ""
    if { [set ${t}::fname] ne "" } {
        if { [file mtime [set ${t}::fname]] != [set ${t}::mtime] } {
            debug 3 "Linked file [set ${t}::fname] modified,\
                     reading again its content"
            LinkFile $t [set ${t}::fname]
        }
    }
    
    if { [set ${t}::code] ne "" } {
        if { [catch {[set ${t}::interp] eval [set ${t}::code]} txt] } {
            debug 1 "Could not interprete templating code. Error: $txt\
                     when executing\n[set ${t}::code]"
            set txt ""
        } else {
            debug 5 "Properly executed templating code in safe interp"
        }
    }
    return $txt
}


proc ::toclbox::templater::parse { t txt } {
    set ${t}::code ""
    if { [catch {Transcode $t $txt} code] } {
        debug 3 "Parsing error: $code"
    } else {
        set ${t}::code $code
        debug 5 "Successfully parsed template text"
    }
    
    return [expr {[set ${t}::code] ne ""}]
}


proc ::toclbox::templater::LinkFile { t fname } {
    debug 4 "Reading content of $fname into template"
    if { [catch {open $fname} fd] } {
        debug 1 "Could not open $fname for reading: $fd"
        return
    }
    set txt [read $fd]
    close $fd
    
    if { [parse $t $txt] } {
        set ${t}::fname $fname
        set ${t}::mtime [file mtime $fname]
    }
}


proc ::toclbox::templater::link { t { fname "" } } {
    if { $fname ne "" } {
        if { [set ${t}::fname] eq "" } {
            LinkFile $t $fname
        } elseif { [set ${t}::fname] ne $fname } {
            LinkFile $t $fname
        }
    }
    
    return [set ${t}::fname]
}


proc ::toclbox::templater::unlink { t } {
    debug 4 "Unlinking previously linked file [set ${t}::fname]"
    namespace inscope $t set fname ""
    namespace inscope $t set mtime ""
}


proc ::toclbox::templater::reset { t } {
    Init $t on
}


proc ::toclbox::templater::delete { t } {
    if { [set ${t}::interp] ne "" } {
        interp delete [set ${t}::interp]
    }
    namespace delete $t
    interp alias {} $t {}
}


proc ::toclbox::templater::config { t args } {
    foreach k [info vars vars::-*] {
        set opt [lindex [split $k :] end]
        ::toclbox::options::parse args $opt -value ${t}::${opt} -default [set vars::$opt]
    }
    Init $t
}


proc ::toclbox::templater::new { args } {
    variable TPL
    
    set t [identifier [namespace current]::templater::]
    # Create namespace to hold templating information and initialise variables.
    namespace eval $t {};
    namespace inscope $t set interp ""
    namespace inscope $t set code ""
    namespace inscope $t set initvars [list]
    namespace inscope $t set fname ""
    namespace inscope $t set mtime ""
    
    eval config $t $args

    set cmds [list]
    foreach cmd [info commands [namespace current]::\[a-z\]*] {
        set cmd [lindex [split $cmd :] end]
        if { $cmd ne "new" } {
            lappend cmds $cmd
        }
    }
    interp alias {} $t {} \
        ::toclbox::control::rdispatch $t [namespace current] $cmds

    return $t
}

package provide toclbox::templater $::toclbox::templater::vars::version
