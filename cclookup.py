#! /usr/bin/env python

"""
Taesoo Kim (tsgatesv@gmail.com)

cclookup is to lookup entries from c++ reference documentation, especially
within emacs.

Have a fun!
"""

import pickle

from urllib        import urlopen
from os.path       import join, dirname, exists

def zip2( iters ) :
    iterobj = iters.__iter__()
    
    while 1 :
        a = iterobj.next()
        b = iterobj.next()
        
        yield ( a, b )

def fetch_page( root, url ) :
    # import only when necessary
    from BeautifulSoup import BeautifulSoup

    soup = BeautifulSoup( urlopen( url ) )

    rtn = []
    for ( keyword, description ) in zip2( soup.findAll( "td" ) ) :
        # ignore newly introduced table (like traits)
        if not keyword.a:
            continue

        # trim keyword like (constructor)
        key = keyword.a.contents[0]
        key = key.replace("(", "")
        key = key.replace(")", "")

        # damm, dirty url link
        url = keyword.a[ "href" ]
        if url.startswith("http"):
            url = url.split("/")[-1]
        
        des = description.contents[0]

        # remove dirty chars
        des = des.replace("&#039;", "")

        rtn.append( ( key.strip(), join( root, url.strip() ), des.strip() ) )
        
    return rtn

if __name__ == "__main__" :
    import optparse
    
    parser = optparse.OptionParser( __doc__.strip() )
    
    parser.add_option( "-d", "--db", dest="db", default="cclookup.db" )
    parser.add_option( "-l", "--lookup", dest="key" )
    parser.add_option( "-u", "--update", dest="url" )
    parser.add_option( "-c", "--cache", action="store_true", default=False, dest="cache")

    ( opts, args ) = parser.parse_args()

    # create db
    try:
        if exists( opts.db ) :
            db = pickle.load( open( opts.db ) )
        else :
            db = []
    except :
        db = []

    # update
    if opts.url :
        from BeautifulSoup import BeautifulSoup

        db   = []
        root = opts.url

        main = BeautifulSoup( open( join( root, "index.html" )  ) )
        body = main.findAll( "div", attrs={ "class" : "level2" } )[0]

        for link in body.findAll( "a" ) :
            url = link[ "href" ].strip()

            cat = url
            cat = cat.replace( "/wiki/", "" )
            cat = cat.replace( "/start", "" ).strip()

            index = link.string.lower()
            index = index.replace( "&amp;", "&" ).strip()

            url = join( root, url.strip() )

            # exceptional case, I like shortname
            if index == "other standard c functions" :
                index = "standard c functions"

            if index.find( "c++" ) != -1 \
                    or index.find( " c " ) != -1 \
                    or index.find( "keywords" ) != -1 \
                    or index.find( "pre-processor" ) != -1 \
                    or index.find( "complex" ) != -1 \
                    or "stl/" in link["href"]:
                print "Indexing", url
            
                for ( key, addr, desc ) in fetch_page( dirname( url ), url ) :
                    
                    key = key.replace( "and ", "" ).replace( "&amp;", "&" ).lower()

                    for subkey in key.split(",") :
                        db.append( ( subkey.strip().encode( "ascii", "ignore" ), 
                                     addr.encode( "ascii", "ignore" ),
                                     cat.encode( "ascii", "ignore" ), 
                                     desc.encode( "ascii", "ignore" ) ) )
                
        # update database
        pickle.dump( db, open( opts.db, "w" ) )

    # cache
    if opts.cache :
        print "\n".join( set( [ item[0] for item in db ] ) )

    # lookup
    if opts.key :
        
        results = []
        
        for item in db :
            if any( [ subitem.find( opts.key ) != -1 for subitem in item ] ) :
                results.append( item )
        
        results.sort()

        print "\n".join( [ "\t".join( item ) for item in results ] )
        

                    
