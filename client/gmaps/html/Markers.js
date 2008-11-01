/* ****************************************************************
      MARKERS
   **************************************************************** */

Markers = {
  gMarkers: undefined,
  icons: undefined,
  pType: undefined,  // assoc. array (index id), indicating whether marker is a source or dest (or both)
  pService: undefined, // assoc array (index id), indicating whether a service is availabel at the marker
  init: function () {
      
      //Markers
      Markers.gMarkers = new Array();
      Markers.pType = new Array();
      Markers.pService = new Array();

  },
  getType: function( id ) {
      if ( typeof Markers.pType[id] == "undefined" ) {
          return undefined;
      }
      return Markers.pType[id];
  },
  setType: function( id, type ) { // src, dst, both
      if ( typeof Markers.pType[id] == "undefined" ) {
          GLog.write( "setType: " + id + " to " + type );
          Markers.pType[id] = type;
      }
      // check not already set to something else
      if ( Markers.pType[id] == type ) {
          // fine
      } else {
          Markers.pType[id] = 'both';
      }
  },
  getService: function( id ) {
    return Markers.pService[id];
  },
  setService: function( id, number ) { // true or false
      GLog.write( "setService: " + id + " to " + number );
      Markers.pService[id] = number;
  },
  getId: function ( srcDomain, dstDomain, item ) {
      // GLog.write( "getId: srcDomain=" + srcDomain + ", dstDomain=" + dstDomain + ", desc=" + item );
      return srcDomain + '__' + dstDomain + '__' + item;
  },
  splitId: function ( id ) {
      var array = undefined;
      if ( array = /^(.*)__(.*)__(.*)$/.exec(id) ) {
          array.shift();
          // GLog.write( "splitId: srcDomain=" + array[0] + ", dstDomain=" + array[1] + ", desc=" + array[2] );
          return array;
      } else {
          GLog.write( "EPIC FAIL! " + array);
      }
      return ( undefined, undefined, undefined );
  },
  isMarker: function( id ) {
      var array = new Array();
      if ( array = /^(.*) to (.*)$/.exec(id) ) {
          return 0;
      }
      return 1;
  },
  create: function( id, point, image ) {
      
      GLog.write( "Markers.create " + id );
      // TOOD: work out if this maker has any services
      var icon = new GIcon(G_DEFAULT_ICON);
      if ( typeof image == "undefined" ) {
          icon.image = "images/blue.png";            
      } else {
          GLog.write( "  using image " + image );
          icon.image = image;
      }
      var markerOptions = { title:id, icon:icon };
      
      Markers.gMarkers[id] = new GMarker( point, markerOptions );
      
      // make double clicks center on the marker
      GEvent.addListener( Markers.gMarkers[id], "dblclick", function() {
          map.setCenter( point );
      });
      // make single clicks the info box
      GEvent.addListener( Markers.gMarkers[id], "click", function() {
          GLog.write( "marker click! infowindow");
          InfoWindow.refreshTab( id );
          // show only links for this marker
          Links.hideAllLinks();
          Links.setDomainVisibilityFromMarker( id, true );
      });

      // add tooltip
      GEvent.addListener( Markers.gMarkers[id], "mouseover", function() {
          Markers.showTooltip( id );
      });
      GEvent.addListener( Markers.gMarkers[id], "mouseout", function() {
          tooltip.style.display = "none";
      });
      GEvent.addListener( Markers.gMarkers[id], "click", function() {
          tooltip.style.display = "none";
      });
      
      return Markers.gMarkers[id];
  },
  add: function ( lat, lng, this_id ) {

    GLog.write( "adding marker '" + this_id + "' at (" + lat + "," + lng + ")" );
    // return if the marker is invalid
    if ( lat == "undefined" || lng == "undefined" ) {
      GLog.write( "Error parsing marker '" + this_id + "' at (" + lat + "," + lng + ")" );
      return undefined;
    }
    
    // check to make sure the marker doesn't already exist
    if ( typeof Markers.gMarkers[this_id] == "undefined" ) {

        Markers.create( this_id, new GLatLng( lat,lng ) );

    } else {
      // TODO: if the long lats are different, then move them
      GLog.write( "FIXME: geo change on marker " + this_id );
    }
    
    return Markers.gMarkers[this_id];    
  },
  get: function( id ) {
      if ( typeof( Markers.gMarkers[id] ) == "undefined" ) {
          GLog.write( "Could not find marker with id " + id );
          return undefined;
      }
      return Markers.gMarkers[id];
  },
  invert: function( e ) {
    for( var id in Markers.gMarkers ) {
      if( Markers.get(id).isHidden() ) {
        Markers.get(id).show();
        sidebar.toggleItem( id, true );
      } else {
        Markers.get(id).hide();
        sidebar.toggleItem( id, false );
      }
    }
    return false;
  },
  show: function( id ) { // overload to determine the type of the marker
      // copy info from marker
      GLog.write( "showing marker " + id + ", type=" + Markers.getType( id ) + ", service=" + Markers.getService( id ) );
      var this_marker = Markers.get(id);
      
      // colour the marker depending on the type
      var colour = "red";
      if ( Markers.getType( id ) == "src" ) {
          colour = "green";
      } else if ( Markers.getType( id ) == "dst" ) {
          colour = "grey";
      } else if ( Markers.getType( id ) == "both" ) {
          colour = "blue";
      }
      
      // place a numeral if there are services on the marker
      if ( Markers.getService( id ) ) {
          colour = colour + Markers.getService(id);
      }
      icon = "images/" + colour + ".png";

      
      GLog.write( "    colour=" + colour );
      this_marker.hide();
      Markers.gMarkers[id] = Markers.create( id, this_marker.getLatLng(), icon );
      map.addOverlay( Markers.gMarkers[id] );
      Markers.gMarkers[id].show();

  },
  hide: function( id ) {
      if ( Markers.get(id) != undefined ) {
          Markers.get(id).hide();
        }
  },
  setVisibility: function( id, state ) {
      if ( state ) {
          Markers.show(id);
      } else {
          Markers.hide(id);
      }
  },
  setDomainVisibility: function( domain, state ) {  // sets all the nodes in the domain to visibility state
      GLog.write( "Marker.setDomainVisibility of domain " + domain + " to " + state );
      for ( xmlUrl in nodesDOM ) {
          GLog.write( "  searching through " + xmlUrl );
          var nodes = nodesDOM[xmlUrl].documentElement.getElementsByTagName("node");
          for( var i = 0; i < nodes.length; i++ ) {
            var this_domain = nodes[i].getAttribute("domain");
            var id = nodes[i].getAttribute("id");
            if ( domain == this_domain ) {
                if ( state == true ) {
                    //GLog.write( "    showing " + id ); 
                    Markers.show( id );
                } else {
                    //GLog.write( "    hiding " + id );
                    Markers.hide( id );
                }
            }
          }
      }
  },
  bounce: function( id ) {
      Markers.get(id).setPoint(center, {draggable: true});
  },
  selectAll: function( e ) {
    for( var urn in gMarkers ) {
      Markers.get(id).show();
      sidebar.toggleItem( id, true );
    }
  },
  selectNoneMarkers: function() {
    for( var urn in gMarkers ) {
      Markers.get(id).hide();
      sidebar.toggleItem( id, false );
    }
  },
  showTooltip: function(id) { // Display tooltips

   tooltip.innerHTML = id;
   tooltip.style.display = "block";

   // Tooltip transparency specially for IE
   if( typeof(tooltip.style.filter) == "string" ) {
       tooltip.style.filter = "alpha(opacity:70)";
   }

   var currtype = map.getCurrentMapType().getProjection();
   var point = currtype.fromLatLngToPixel( map.fromDivPixelToLatLng( new GPoint(0,0), true ), map.getZoom());
   var offset = currtype.fromLatLngToPixel( Markers.get(id).getLatLng(), map.getZoom() );
   var anchor = Markers.get(id).getIcon().iconAnchor;
   var width = Markers.get(id).getIcon().iconSize.width + 6;
  // var height = tooltip.clientHeight +18;
   var height = 10;
   var pos = new GControlPosition(G_ANCHOR_TOP_LEFT, new GSize(offset.x - point.x - anchor.x + width, offset.y - point.y -anchor.y - height)); 
   pos.apply(tooltip);
  }
}

