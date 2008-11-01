/* ****************************************************************
      INFOWINDOW
   **************************************************************** */

InfoWindow = {
    activeId: undefined,
    init: function () {
        Markers.gMarkers = new Array();
    },
    // add a infowindowtab to the marker id of servcice type
    add: function ( id, serviceType ) {
        GLog.write( "adding InfoWindow '" + id + "'" );
    },
    get: function( id ) {
      GLog.write( "Creating tabs for '" + id + "'" );
      // determine what tabs to create for this urn
      var tabs = new Array();
      // always have an info tab
      tabs.push( new GInfoWindowTab( "Info", id ) );
      // how add all the other tabs - iterate through the xml and add on all the with same src/dst/description

      for ( xmlUrl in nodesDOM )
      {
          GLog.write( "  searching through '" + xmlUrl + "'");
          
          if( Markers.isMarker( id ) ) {
              
              var nodes = nodesDOM[xmlUrl].documentElement.getElementsByTagName("node");
              for( var i = 0; i < nodes.length; i++ )
              {	        
                  if ( nodes[i].getAttribute("id") == id ) {

                      GLog.write( "    found marker id '" + id + "' in uri '" + xmlUrl + "'" );

                      // now go through the ma definitions and build an info tab for it
                      var els = nodes[i].getElementsByTagName("service");
                      // updaate marker service
                      for( var j = 0; j < els.length; j++ ) {
                      
                          var serviceType = els[j].getAttribute("serviceType");
                          var eventType = els[j].getAttribute("eventType");
                          var accessPoint = els[j].getAttribute("accessPoint");
                      
                          GLog.write( "  found service=" + serviceType + ", eventType=" + eventType + ", accessPoint='" + accessPoint );
                          // fetch the page template from the service	
                          var src = '&eventType=' + eventType;
                          src = src + '&accessPoint=' + accessPoint;

                          var html = eventType + ' @ ' + accessPoint + '<br/><center>__CONTENT__</center>'

                          src = '?mode=discover' + src;
                          html = html.replace( /__CONTENT__/g, "<p><input type=\"submit\" value=\"Query Service\" onclick=\"discover(\'" + src + "'); GEvent.trigger( Markers.get('" + id + "'), 'click' );\" /></p>" );

                          GLog.write( '  building marker tab: ' + html ); 
                          tabs.push( new GInfoWindowTab( serviceType, html ) );
                      }
                  }
              }
          } else {
              
              var node = Links.splitId( id );
              var src_id = node[0];
              var dst_id = node[1];

              var links = nodesDOM[xmlUrl].documentElement.getElementsByTagName("link");
              //GLog.write( "  looking for " + src_id + ", " + dst_id + ", elements = " + links.length );
              for( var i = 0; i < links.length; i++ ) {
                  
                  var this_src = links[i].getAttribute("src");
                  var this_dst = links[i].getAttribute("dst");
                  
                  if ( this_src  == src_id 
                        && this_dst  == dst_id ) {
                   
                    var els = links[i].getElementsByTagName("urn");
                    for( var j = 0; j < els.length; j++ ) {
                        
                        var serviceType = els[j].getAttribute("serviceType");
                        var eventType = els[j].getAttribute("eventType");
                        var accessPoint = els[j].getAttribute("accessPoint");
                        var urn = els[j].firstChild.nodeValue;
                        
                        GLog.write( "    found link urn=" + urn + ", service=" + serviceType + ", eventType=" + eventType + ", accessPoint='" + accessPoint );
 
                        var src = '&eventType=' + eventType;
                        src = src + '&accessPoint=' + accessPoint;
                        
                        // use the key if we have one
                        var a = urn.match( /key=((\w|\,)+):?/ );
                        if ( a.length > 0 ){
                            src = src + '&key=' + a[1];
                        } else {
                            src = src + '&urn=' + urn;
                        }
                        
                        var html = eventType + ' @ ' + accessPoint + ' for urn ' + urn + '<br/><center>__CONTENT__</center>'

                        src = '?mode=graph' + src;
                        html = html.replace( /__CONTENT__/g, "<p><img width=\"497\" height=\"168px\" src=\"" + src + "\"/></p>" );

                        GLog.write( '  building link tab: ' + html ); 
                        tabs.push( new GInfoWindowTab( serviceType, html ) );
                    }
                            
                  }
              }
              
          }
      }
      return tabs;
    },
    refresh: function() {
      if( ! map.getInfoWindow().isHidden() )
        InfoWindow.refreshTab( InfoWindow.activeId );
    },
    refreshTab: function( id ) {
        GLog.write( 'refreshTab: ' + id );
        if ( id == undefined ) {
            id = InfoWindow.activeId;
        } else {
            InfoWindow.activeId = id;
        }
        if ( Markers.isMarker( id ) ) {
            var tabs = InfoWindow.get( id );
            var number = map.getInfoWindow().getSelectedTab();
            Markers.get(id).openInfoWindowTabsHtml( tabs, {selectedTab:number} );
        } else {
            // not need to force the tab open as gevent should have already hooked in for click
            // Links.openInfoWindowTabHtml( id );
            // refresh tab window
            //map.updateCurrentTab();
        }

    },
    focus: function( id ) {
        GLog.write( 'focus: ' + id );
        Markers.activeMarker = id;
        InfoWindow.refreshTab( id );
        map.getInfoWindow().hide();
        map.updateInfoWindow();
        map.getInfoWindow().show();
    }

}

