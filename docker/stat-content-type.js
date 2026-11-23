function fix_type(r) {
    // nginx-rtmp sets Content-Type but leaves content_type_len at 0.
    // The XSLT filter then skips /stat. Setting the header here fills that length.
    // Leave 401 and 403 responses alone so the filter does not parse their HTML bodies.
    if (r.status !== 200) {
        return;
    }
    r.headersOut["Content-Type"] = "text/xml";
}

export default { fix_type };
