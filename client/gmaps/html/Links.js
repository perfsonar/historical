/* ****************************************************************
      LINKS
   **************************************************************** */

Links = {
  gLinks: undefined,
  init: function () {
      
      //Markers
      Links.gLinks = new Array();
      
  },
  getId: function ( src, dst ) {
      return src + ' to ' + dst;
  },
  splitId: function ( id ) {
      var array = new Array();
      if ( array = /^(.*) to (.*)$/.exec(id) ) {
          array.shift();
          return array;
      } else {
          GLog.write( "EPIC FAIL! on '" + id + "' for " + array );
      }
      return ( undefined, undefined );
  },
  isLink: function( id ) {
      var array = new Array();
      if ( array = Links.splitId( id ) ) {
          if( array.length() == 2 ) {
              return 1;
          }
      }
      return 0;
  },
  add: function ( src_id, dst_id ) {

    var this_id = Links.getId( src_id, dst_id );
    GLog.write( "adding link id: '" + this_id + "', from '" + src_id + "' to '" + dst_id  + "'" );


    // check to make sure the marker doesn't already exist
    if ( typeof Links.gLinks[this_id] == "undefined" ) {

        // update type and service of marker
        var src = Markers.get( src_id );
        var dst = Markers.get( dst_id );

        var polyOptions = {geodesic:true};
        var polyline = new GPolyline([
          src.getLatLng(),
          dst.getLatLng()
        ], "#ff0000", 3, 1, polyOptions);

        Links.gLinks[this_id] = polyline;

        // make single clicks the info box
        GEvent.addListener( Links.gLinks[this_id], "click", function() {
            InfoWindow.refreshTab( this_id );
        });
        // intiaially hide the links until the source is clicked on
        Links.hide( this_id );
    }

    return Links.gLinks[this_id];
  },
  get: function( id ) {
    return Links.gLinks[id];  
  },
  initInfoWindow: function( id ) {
    GLog.write( "  initiating tabs for link infoWindow " + id );
    GEvent.addListener( Links.get(id), 'click', function(point) { 
      GLog.write( "Showing infoWindow for link '" + id + "'");
      var tabs = InfoWindow.get( id );
      var number = map.getInfoWindow().getSelectedTab();
      GLog.write( "  links openinfowindow tab=" + number + " @ (" + point.lat() + ", " + point.lng() + ")" );
      map.openInfoWindowTabsHtml( point, tabs, {selectedTab:number} ); 
    } );
  },
  show: function( id ) {
      Links.initInfoWindow( id );
      map.addOverlay(Links.gLinks[id]);
      Links.get(id).show();
  },
  hide: function( id ) {
      Links.get(id).hide();
  },
  setVisibility: function( id, state ) {
      GLog.write( "setVisibilty of " + id + " to " + state );
      if ( state == false ) {
          Links.show( id );
      } else {
          Links.hide( id );
      }
  },
  setDomainVisibility: function( domain, state ) {
      GLog.write("Links.setDomainVisibilty of " + domain + " to " + state );
      for ( xmlUrl in nodesDOM ) {
          GLog.write( "  going through " + xmlUrl );
          var link = nodesDOM[xmlUrl].documentElement.getElementsByTagName("link");
          for( var i = 0; i < link.length; i++ ) {
            var this_srcDomain = link[i].getAttribute("srcDomain");
            
            // if this src_id matches, then show the link
            if ( this_srcDomain == domain ) {
                
                var this_src = link[i].getAttribute("src");
                var this_dst = link[i].getAttribute("dst");
                var this_id = Links.getId( this_src, this_dst );
                
                if ( state == true ) {
                    Links.show( this_id );
                } else {
                    Links.hide( this_id );
                }
            }
          }
      }
  },
  setDomainVisibilityFromMarker: function( src_id, state ) {
      GLog.write("Links.setDomainVisibiltyFromMarker of " + src_id + " to " + state );
      for ( xmlUrl in nodesDOM ) {
          GLog.write( "  going through " + xmlUrl );
          var link = nodesDOM[xmlUrl].documentElement.getElementsByTagName("link");
          for( var i = 0; i < link.length; i++ ) {
            var this_src = link[i].getAttribute("src");
            var this_dst = link[i].getAttribute("dst");
            // GLog.write( "    looking at link " + this_src + ", " + this_dst );
            var this_id = Links.getId( this_src, this_dst );
            
            // if this src_id matches, then show the link
            if ( this_src == src_id ) {
                if ( state == true ) {
                    Links.show( this_id );
                } else {
                    Links.hide( this_id );
                }
            }
          }
      }
  },
  hideAllLinks: function( ) {
      GLog.write( "hideAllLinks");
      for ( xmlUrl in nodesDOM ) {
          GLog.write( "  going through " + xmlUrl );
          var link = nodesDOM[xmlUrl].documentElement.getElementsByTagName("link");
          for( var i = 0; i < link.length; i++ ) {
            var this_src = link[i].getAttribute("src");
            var this_dst = link[i].getAttribute("dst");
            // GLog.write( "    looking at link " + this_src + ", " + this_dst );
            var this_id = Links.getId( this_src, this_dst );
            Links.hide( this_id );
        }
    }
  },
  focus: function( id ) {
      GLog.write( "Focus on link '" + id + "'");
      Links.show( id );
      Sidebar.setCheckBox( 'check-' + id + ":Link" )
  }
}

