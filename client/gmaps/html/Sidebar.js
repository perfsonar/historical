
Sidebar = {
    contents: undefined,
    target: undefined,
    checkmenu: undefined,
    init: function ( element ) {
      Sidebar.target = element;
      Sidebar.checkmenu = new Object();
      return false;
    },
    clear: function() {
      Sidebar.contents = '';
      return false;
    },
    normalise: function ( str ) {
    	return str.replace( /\-/g, '' );
    },
    add: function( i, j, k ) {
        if( debug )
            GLog.write( "adding to sidebar " + i + ", " + j + ", " + k );

        // init datastructures when necessary		
        if ( ! Sidebar.checkmenu[i] ) {
        	Sidebar.checkmenu[i] = new Object;
        }
        if ( ! Sidebar.checkmenu[i][j] ) {
        	Sidebar.checkmenu[i][j] = new Array();
        }

        Sidebar.checkmenu[i][j].push( k );

        return false;
    },
    get: function( id ) {
        // TODO: add serviceType to node gather
        if( debug )
  	        GLog.write( "getting checkbox state '" + id + "'" );
  	  return document.getElementById( id );
    },
    getCheckBoxState: function( id ) {
        var sidebar_id = 'check-' + id;
        var ret = Sidebar.get( sidebar_id ).checked;
        if( debug )
            GLog.write( 'state of ' + sidebar_id + " is " + ret )
        return ret;
    },
	setCheckBox: function( id, state ) {
        var sidebar_id = 'check-' + id;
        var checkbox = Sidebar.get( sidebar_id );
        if( debug )
            GLog.write( "setting checkbox '" + sidebar_id + "' to " + state);
        if ( state == true ) {
          checkbox.checked = true;
        } else {
          checkbox.checked = false;
        }
	},
	getLinkId: function( id ) {
	    return id + ':Link';
	},
	splitLinkId: function( sidebar_id ) {
        var id = sidebar_id.replace( ':Link', '' );
        return id;
    },
    getMarkerId: function( id, serviceType ) {
        return id + ":" + serviceType;
    },
    splitMarkerId: function( sidebar_id ) {
        var a = new Array();
        if ( a = /^(.*):(.*)$/.exec(sidebar_id) ) {
            return a[1];
        }
        return undefined;
    },
    setLink: function( sidebar_id, state ) {
        if( debug )
            GLog.write( "Sidebar.setLink: " + sidebar_id + " to " + state );
        // strip out uid
        var id = Sidebar.splitLinkId( sidebar_id );
        if ( state ) {
            Sidebar.setCheckBox( sidebar_id, true );
            Links.show( id );
        } else {
            Sidebar.setCheckBox( sidebar_id, false );
            Links.hide( id );
        }
	},
	updateChildren: function( sidebar_id ) {
        // goes through all of dom and updates the node/link show status
        if( debug )
            GLog.write( "updateChildren: looking for '" + sidebar_id + "'");
        // look for all inputs
        var treeId = 'tree-' + sidebar_id;
        var checkBoxState = Sidebar.getCheckBoxState( sidebar_id );

        var checkboxEls = Sidebar.get( treeId ).getElementsByTagName("input");
        if( debug )
            GLog.write( "  found " + checkboxEls.length + " check boxes for parent " + sidebar_id );
        for ( var i=0; i<checkboxEls.length; i++ ){
            if( debug )
                GLog.write( "  looking at index " + i );
            var checkboxId = checkboxEls[i].getAttribute( "id" ).replace( /^check-/, "");
            if ( Markers.isMarker( checkboxId ) ) {
                var id = Sidebar.splitMarkerId( checkboxId );          
                if( debug )
                    GLog.write( "  changing marker visibiilty " + id + " to " + checkBoxState );
                Markers.setVisibility( id, checkBoxState );
            } else {
                if( debug )
                    GLog.write( "  changing link visibiilty of " + checkboxId + " to " + checkBoxState );                
                Sidebar.setLink( checkboxId, checkBoxState );
            }
        }
	},
	setDomainVisibility: function( id, state ) {
        if( debug )
	        GLog.write( "Sidebar.setDomainVisibility of " + id + " to " + state );
	    // work out the sidebar id
	    Markers.setDomainVisibility( id, state );
	    Links.setDomainVisibility( id, state )
	},
	sort: function( hash ) {
	    var sortable = new Array();
	    for ( var i in hash ) {
	        sortable[sortable.length] = i;
	    }
	    return sortable.sort();
	},
    show: function( e ) {
        if( debug )
            GLog.write( "Sidebar:show");

        var allLinkIds = new Array();

        Sidebar.clear();
        Sidebar.contents =  '<ul id="tree-checkmenu" class="checktree">'; 

        var l1 = Sidebar.sort( Sidebar.checkmenu );
        for ( var x=0; x<l1.length; x++ ) {
            var i = l1[x];
            var l1Id = i;
            // determine if we have a domain at this level or a node
            var l1checkBoxCode = "var state = Sidebar.getCheckBoxState( '" + l1Id + "' ); Sidebar.setDomainVisibility( '" + l1Id + "', state );";
            Sidebar.contents += '<li id="show-' + l1Id + '">'
            	+ '<input id="check-' + l1Id + '" type="checkbox" class="minus" onchange="' + l1checkBoxCode + '"/>' + i
            	+ '<span id="count-' + l1Id + '" class="count"></span>'
            	+ '<ul id="tree-' + l1Id + '">';

            // need unique id for this level's li's
            var l2 = Sidebar.sort( Sidebar.checkmenu[i] );
            for( var y=0; y<l2.length; y++ ) {
                var j = l2[y];

                var l2Id = undefined;
                if ( 1 ) {
                    l2Id = Links.getId( i, j ); // this kinda doesn't make sense for markers, but we just need a unique id
                }
                
                // var l2checkBoxCode = "var state = Sidebar.getCheckBoxState( '" + l2Id + "' ); Markers.setVisibility( '" + l2Id  +  "', state )";
                var l2checkBoxCode = "Sidebar.updateChildren( '" + l2Id  + "' );";
                
                // TODO: ensure there are no links within, if markers exist then change class to 'plus'
                Sidebar.contents += '<li id="show-' + l2Id + '">' 
                    + '<input id="check-' + l2Id + '" type="checkbox" onchange="' + l2checkBoxCode + '"/>' + j
                    + '<span id="count-' + l2Id + '" class="count"></span>'
                    + '<ul id="tree-' + l2Id + '">';

            	for( var k = 0; k < Sidebar.checkmenu[i][j].length; k++ ) {

                      var liStyle = '';
                    if ( k == Sidebar.checkmenu[i][j].length - 1 )
                    	liStyle = ' class="last"';

                    // for nodes; use index of FQDN node at j, and click brings up infoWindow of node
                    // TODO: for links, use id as index, and instantiate a click event along half it's length
                    var checkBoxCode = undefined;   // js code for when check box is toggled
                    var clickCode = undefined;      // js code for when the node is toggled
                    
                    var clickName = Sidebar.checkmenu[i][j][k];      // string of what to put on label
                    
                    var l3checkBoxState = false;
                    var l3Id = undefined;
                    
                    if ( Markers.isMarker( Sidebar.checkmenu[i][j][k] ) ) {
                        l3Id = Sidebar.getMarkerId( j, Sidebar.checkmenu[i][j][k] );
                        checkBoxCode = "javascript:var state = Sidebar.get( 'check-" + l3Id + "' ).checked; Markers.setVisibility( '" + j + "', state );";
                        // TODO: open specific serviceType tab on click
                        clickCode = "javascript:InfoWindow.focus( '" + j + "' );"
                        l3checkBoxState = true;

                    } else {
                        l3Id = Sidebar.getLinkId( Sidebar.checkmenu[i][j][k] );
                        clickCode = "javascript: Sidebar.setLink( '" + l3Id + "', true ); Links.focus( '" + l3Id + "' );";
                        checkBoxCode = "javascript: var state = Sidebar.getCheckBoxState( '" + l3Id + "' ); Sidebar.setLink( '" + l3Id + "', state );";
                    }

                    var l3checkBoxText = "";
                    if ( l3checkBoxState )
                        l3checkBoxText = "checked";

                    Sidebar.contents +=
                        '<li' + liStyle + '>'
                            + '<input id="check-' + l3Id + '" type="checkbox" ' + l3checkBoxText + ' onchange="' + checkBoxCode + '"/>'
                            + '<a href="' + clickCode + '">' + clickName + '</a>'
                            + '</li>';
            	}
	
            	Sidebar.contents += '</ul>'; // tree
            	Sidebar.contents += '</li>'; // show
            }
	
            Sidebar.contents += '</ul>'; //tree
            Sidebar.contents += '</li>' //show
        }

        Sidebar.contents += '</ul>'; //checkmennu

		Sidebar.refresh();

		return false;
	},
	refresh: function( e ) {
        if( debug )
	        GLog.write( "Refreshing sidebar: " + Sidebar.target );
	  var list = document.getElementById( Sidebar.target );
	  list.innerHTML = Sidebar.contents;
	  
	  // instantiate the list
	  checkmenu = new CheckTree('checkmenu');		
	  checkmenu.init();
	  
	  return false;
	},
	setContent: function( html ) {
	  var content = document.getElementById( Sidebar.target );
	  content.innerHTML = html;
	  return false;
	}
}
