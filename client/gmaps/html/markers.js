/* ****************************************************************
      MARKERS
   **************************************************************** */

markers = {
  gmarkers: undefined,
  activeMarker: undefined,
  init: function () {
      markers.gmarkers = new Array();
  },
  add: function ( lat, lng, urn ) {
    //google.maps.Log.write( "Adding marker '" + urn + "' at (" + lat + "," + lng + ")" );
    // return if the marker is invalid
    if ( urn == "" || lat == "undefined" || lng == "undefined" ) {
      google.maps.Log.write( "Error parsing marker '" + urn + "' at (" + lat + "," + lng + ")" );
      return undefined;
    }
    var point = new google.maps.LatLng( lat,lng );
    var marker = new google.maps.Marker(point, {title:urn});
    // make double clicks center on the marker
    google.maps.Event.addListener( marker, "dblclick", function() {
        map.setCenter( point );
    });
    // make single clicks the info box
    google.maps.Event.addListener( marker, "click", function() {
        markers.refreshInfoWindowTab( urn );
    });

    // check to make sure the marker doesn't already exist
    if ( typeof markers.gmarkers[urn] == "undefined" ) {
      markers.gmarkers[urn] = marker;
      return marker;
    } else {
      // TODO: if the long lats are different, then move them
      return undefined;
    }
  },
  fromUrn: function( urn ) {
    // try standard domain/node/port
    //google.maps.Log.write( 'fromUrn: in=' + urn );
    var id = urn.match(/^urn\:ogf\:network\:domain\=(.*)\:node\=(.*)\:port\=(.*)/);
    // otherwise, try path
    if ( id == null) {
      id = urn.match(/^urn\:ogf\:network\:path\=(.*) to (.*)/ );
    }

    //remove the first element (which is entire string)
    id.shift();
    //google.maps.Log.write( "fromUrn: " + id );
    return id;
  },
  toUrn: function( id ) { //domain, node, port ) {
    var urn;

    if ( id.length == 3 ) {
      // if the first is path, then it's a path urn...
      if ( id[0] == 'path' ) {
        id.shift();
      }
      // standard domain/node/port
      urn = 'urn:ogf:network:domain=' + id[0] + ':node=' + id[1] + ':port=' + id[2];
    }

    if ( id.length == 2 ) {
      // path urn
      urn = 'urn:ogf:network:path=' + id[0] + ' to ' + id[1];
    }
    //google.maps.Log.write( "Constructed '" + urn + "' from input=" + id );
    return urn;
  },
  invert: function( e ) {
    for( var urn in markers.gmarkers ) {
      if( gmarkers[urn].isHidden() ) {
        markers.gmarkers[urn].show();
        sidebar.toggleItem( urn, true );
      } else {
        markers.gmarkers[urn].hide();
        sidebar.toggleItem( urn, false );
      }
    }
    return false;
  },
  selectAll: function( e ) {
    for( var urn in gmarkers ) {
      markers.gmarkers[urn].show();
      sidebar.toggleItem( urn, true );
    }
  },
  selectNoneMarkers: function() {
    for( var urn in gmarkers ) {
      markers.gmarkers[urn].hide();
      sidebar.toggleItem( urn, false );
    }
  },
  getUrn: function( urn ) {
    //google.maps.Log.write( 'getUrn: ' + urn );
    var marker = eval( markers.gmarkers[urn] );
    if ( typeof marker == "undefined") {
      var id = markers.fromUrn( urn );
      for( var i = 1; i < id.length; i++ ) {
        id[i] = id[i].replace( /\//g, "\%2F" ); 
        id[i] = id[i].replace( /\:/g, "\%3A" ); 
      }
      urn = markers.toUrn( id ); //[1], id[2], id[3] );
      google.maps.Log.write( "Changed urn to "  + urn );
      marker = markers.gmarkers[urn];
    }
    return urn;
  },
  getTabs: function( urn ) {
    google.maps.Log.write( "Creating tabs for '" + urn + "'" );
	  // determine what tabs to create for this urn
	  var tabs = new Array();
	  // always have an info tab
	  tabs.push( new google.maps.InfoWindowTab( "Info", urn ) );
	  // how add all the other tabs
	  for ( xmlUrl in nodesDOM ) {
	    var nodes = nodesDOM[xmlUrl].documentElement.getElementsByTagName("node");
	    for( var i = 0; i < nodes.length; i++ ) {
	      if ( nodes[i].getAttribute("urn") == urn ) {
	        google.maps.Log.write( "Found in uri '" + xmlUrl + "'" );
	        // now go through the ma definitions
	        // determine the ma's to use for this node
		var els = nodes[i].getElementsByTagName("ma");
		for( var j = 0; j < els.length; j++ ) {
			var type = els[j].getAttribute("type");
			var uri = els[j].childNodes[0].nodeValue;
			google.maps.Log.write( "Found MA type=" + type + " uri='" + uri + "'" );
			// fetch the page template from the service	
			var html = infoWindowGraph.replace( /__TYPE__/g, type );
			html = html.replace( /__URN__/g, escape( urn ).replace( /\//g, '%2F' ) );
			html = html.replace( /__URI__/g, escape( uri ).replace( /\//g, '%2F')  );
			google.maps.Log.write( 'HTML: ' + html ); 
		      	tabs.push( new google.maps.InfoWindowTab( type, '<center>' + html + ' </center>' ) );
		}
	      }
	    }
	  }
	  return tabs;
	},
	refreshInfoWindow: function() {
	  if( ! map.getInfoWindow().isHidden() )
	    markers.refreshInfoWindowTab( markers.activeMarker );
	},
	toggle: function( urn ) {
      urn = markers.getUrn( urn );
      markers.gmarkers[urn].isHidden() ? markers.gmarkers[urn].show() : markers.gmarkers[urn].hide();	
	},
	refreshInfoWindowTab: function( urn ) {
          urn = markers.getUrn( urn );
	  markers.activeMarker = markers.getUrn( urn ); 
	  var tabs = markers.getTabs( urn );
	  var number = map.getInfoWindow().getSelectedTab();
          markers.gmarkers[urn].openInfoWindowTabsHtml( tabs, {selectedTab:number} ); 
	},
	focusInfoWindow: function( urn ) {
	  markers.refreshInfoWindowTab( urn );
	  map.getInfoWindow().hide();
	  map.updateInfoWindow();
	  map.getInfoWindow().show();
	}
	
}

