/* ****************************************************************
  XML Polling
 **************************************************************** */

IO = {
    // retrieves a list of all the gls and plots them on the map
    getGLS: function() {
        IO.discover( '?mode=getGLS' );
        //      discover( '?mode=discover&accessPoint=http://tukki.fnal.gov:9990/perfSONAR_PS/services/gLS');
        //      discover( '?mode=discover&accessPoint=http://nptoolkit.grnoc.iu.edu:8095/perfSONAR_PS/services/hLS');
        //IO.discover( '?mode=discover&accessPoint=http://nptoolkit.grnoc.iu.edu:8075/perfSONAR_PS/services/pinger/ma');
    },

    // retrieves the nodes for the uri
    discover: function( uri ) {

        Help.discover( uri );

        if( debug )
            GLog.write( "Fetching markers from '" + uri + "'");


        // deal with timeouts etc
        GDownloadUrl( uri, function(doc,response) {

          // downloaded okay
          if ( response == 200 ) {

            Sidebar.clear();
            Sidebar.setContent('<p align="center">Please wait.<br>Fetching perfSONAR information: <br>This could take some time...<br><img src="spinner.gif"/></p>' );
            Sidebar.refresh();

            if ( typeof nodesDOM[uri] == "object" ) {
              // wipe out the out one to reload
              nodesDOM[uri] = undefined;
              if( debug )
                GLog.write("Clearing xml cache of '" + uri + "'" );
            }
            nodesDOM[uri] = GXml.parse(doc);

            if( debug )
                GLog.write( "Adding Nodes..." );
            var nodes = nodesDOM[uri].documentElement.getElementsByTagName("node");
            if( debug )
                GLog.write( "  completed fetching " + nodes.length + " markers from '" + uri + "'");
            var markerCount = 0;
            var serviceCount = 0;
            var linkCount = 0;

            for (var i = 0; i < nodes.length; i++) {

              var lat = nodes[i].getAttribute("lat");
              var lng = nodes[i].getAttribute("lng");

              var domain = nodes[i].getAttribute("domain");
              var id = nodes[i].getAttribute("id");

              // if there is no determinable long/lat, place it in the bermuda triagle
              if ( ( lat == "" || lat == 'NULL' ) || ( lng == "" || lng == 'NULL' ) ) {
                lat = '26.511129';
                lng = '-71.48186';
                if( debug )
                    GLog.write( "Marker '" + id + "' does not contain valid coordinates, placing in Bermuda Triangle" );
              }

              Markers.add( lat, lng, id );
              // if there are service element defined, then assume services on this node
              var els = nodes[i].getElementsByTagName("service");
              var n = 0;
              for ( var j=0; j<els.length; j++ ) {
                var serviceType = els[j].getAttribute( 'serviceType' );
                Sidebar.add( domain, id, serviceType );
                if ( typeof services[id] == "undefined" )
                    services[id] = new Array();
                services[id][serviceType] = 1;
                for( var j in services[id] )
                  n++;
                Markers.setService( id, n );
                serviceCount++;
              }

              // TODO: add urn's (utilisation)
              markerCount++;

            } // for
            if( debug )
                GLog.write( "Added " + markerCount + " new markers" );

            if( debug )
                GLog.write( "Adding Links..." );
            var links = nodesDOM[uri].documentElement.getElementsByTagName("link");
            if( debug )
                GLog.write( "  completed fetching " + links.length + " links from '" + uri + "'");
            for ( var i = 0; i < links.length; i++ ) {

              var src_id = links[i].getAttribute("src");
              var dst_id = links[i].getAttribute("dst");
              var src_domain = links[i].getAttribute("srcDomain");
              var dst_domain = links[i].getAttribute("dstDomain");

              Links.add( src_id, dst_id );
              Sidebar.add( src_domain, dst_domain, Links.getId( src_id, dst_id ) );

              Markers.setType( src_id, 'src' );
              Markers.setType( dst_id, 'dst' );
              
              linkCount++;

            }
            if( debug )
                GLog.write( "Added " + linkCount + " new links" );

            Sidebar.show();

            // can only update/how the markers here as we need to process links and services to determine
            // the appropriate type fo the marker first
            for (var i = 0; i < nodes.length; i++) {
              var id = nodes[i].getAttribute("id");
              Markers.show( id );
            }

            // refresh window
            InfoWindow.show();

            Help.discovered( uri, markerCount, linkCount, serviceCount );

            // timeout
          } else if ( response == -1 ) {
            if( debug )
                GLog.write( "Request for '" + uri + "' timed out" );
            Help.timeOut( uri );
          } else {
            if( debug )
              GLog.write( "unknown response code returned " + response );
            Help.unknownResponse( uri, response );
          }
        });
    }
    
}

