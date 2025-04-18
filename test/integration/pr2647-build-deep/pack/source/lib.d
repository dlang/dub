module lib;

import url;

string getDlangUrl()
{
    URL url;
    with(url)
    {
        scheme = "https";
        host = "dlang.org";
    }
    return url.toString();
}
