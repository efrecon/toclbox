# Default options
array set options {
    -output  {stdout}
    -lines   10
    -blank   "\t"
    -linesep ""
    -binary  off
}
# "parse" options
array set options $argv

foreach fd $options(-output) {
    if { $options(-binary) } {
        fconfigure $fd -encoding binary -translation binary
    }
    for {set i 0} {$i < $options(-lines)} {incr i} {
        if { $options(-linesep) eq "" } {
            puts $fd $i
        } else {
            puts -nonewline $fd $i
            puts -nonewline $fd $options(-linesep)
        }
        if { $options(-blank) ne ""} {
            if { $options(-linesep) eq "" } {
                puts $fd $options(-blank)
            } else {
                puts -nonewline $fd $options(-blank)
                puts -nonewline $fd $options(-linesep)
            }
        }
    }
}