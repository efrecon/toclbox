proc http_version {} {
    return [package require http]
}

proc http_get { url } {
    package require http
    set tok [::http::geturl $url]
    set ncode [::http::ncode $tok]
    ::http::cleanup $tok
    return $ncode
}