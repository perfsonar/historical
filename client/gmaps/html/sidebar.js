
sidebar = {
	contents: undefined,
    target: undefined,
    checkmenu: undefined,
	init: function ( element ) {
	  sidebar.target = element;
	  sidebar.checkmenu = new Object();
	  return false;
	},
	clear: function() {
	  sidebar.contents = '';
	  return false;
	},
	normalise: function ( str ) {
		return str.replace( /\-/g, '' );
	},
	add: function( urn ) {
		// split the domain/node/port
		var id = markers.fromUrn( urn ); 
		//google.maps.Log.write( "Adding to sidebar '" + urn + "' - domain=" + id[1] + " node=" + id[2] + " port=" + id[3] );
		//google.maps.Log.write( 'sidebar:add ' + urn + ' -> ' + id + ' length=' + id.length );
		// remove all spaces

		// if path, then make the top level as 'path'
		if ( id.length == 2 ) {
			id.unshift( 'path' );
		}
		google.maps.Log.write( 'sidebar:add ' + id );
		// init datastructures when necessary		
		if ( ! sidebar.checkmenu[id[0]] ) {
			sidebar.checkmenu[id[0]] = new Object;
		}
		if ( ! sidebar.checkmenu[id[0]][id[1]] ) {
			sidebar.checkmenu[id[0]][id[1]] = new Array();
		}			
		
		sidebar.checkmenu[id[0]][id[1]].push( id[2] );
		
		return false;
	},
	show: function( e ) {
		google.maps.Log.write( "Showing menu");

		sidebar.clear();
		sidebar.contents = 
				'<ul id="tree-checkmenu" class="checktree">'; 

		for ( var i in sidebar.checkmenu ) {
			sidebar.contents += '<li id="show-' + i + '">'
				+ '<input id="check="' + i + '" type="checkbox" checked/>' + i
				+ '<span id="count-' + i + '" class="count"></span>'
				+ '<ul id="tree-' + i + '">';
				
			for( var j in sidebar.checkmenu[i] ) {
				var str = i + '_' + j;
				sidebar.contents += '<li id="show-' + str + '">' 
					+ '<input id="check-' + str + '" type="checkbox" onclick="sidebar.toggle(\'' + i + '\', \'' + j  + '\', \'check-' + str + '\')" checked/>' + j
					+ '<span id="count-' + str + '" class="count"></span>'
					+ '<ul id="tree-' + str + '">';
					
				for( var k = 0; k < sidebar.checkmenu[i][j].length; k++ ) {

					var urn;
					var array = new Array();
					if( i == 'path') {
						// nothing
					} else {
						array.push( i );
					}

					// build urn
					array.push( j );
					array.push( sidebar.checkmenu[i][j][k] );

					urn = markers.toUrn( array ); 
					//google.maps.Log.write( 'sidebar:show ' + array + ' -> ' + urn );

					var liStyle = '';
					if ( k == sidebar.checkmenu[i][j].length - 1 )
						liStyle = ' class="last"';

					sidebar.contents +=
						'<li' + liStyle + '>'
						+ '<input type="checkbox" onclick="javascript:markers.toggle(\'' + urn + '\')" checked/>' 
						+ '<a href="javascript:markers.focusInfoWindow(\'' + urn + '\');">'  
						+ sidebar.checkmenu[i][j][k]
						+ '</a>'
						+ '</li>';
				}
				
				sidebar.contents += '</ul>'; // tree
				sidebar.contents += '</li>'; // show
			}
				
			sidebar.contents += '</ul>'; //tree
		    sidebar.contents += '</li>' //show
		}

		sidebar.contents += '</ul>'; //checkmennu

		sidebar.refresh();		
		return false;
	},
	toggle: function( domain, node, checkbox ) {
		google.maps.Log.write( "sidebar:toggle !");
	  var urns = new Array();
	  if( domain == "undefined" )
		domain = '(.*)';
	  if( node == "undefined" )
		node= '(.*)';
		var regexp = new RegExp( markers.toUrn( domain, node, '' )  );
		for ( xmlUrl in nodesDOM ) {
            var nodes = nodesDOM[xmlUrl].documentElement.getElementsByTagName("node");
            for( var i = 0; i < nodes.length; i++ ) {
				var urn = nodes[i].getAttribute("urn");
				if ( urn.match( regexp ) ){
					urns.push( urn );
					google.maps.Log.write( "Adding to toggle list: " + urn );
				}
			}
	  }
	  var currentState = document.getElementById( checkbox ).checked;
	  google.maps.Log.write( "State: " + checkbox + " is " + currentState );
	  for ( var i=0; i<urns.length; i++ ) {
		var urn = markers.getUrn( urns[i] );
		currentState ? markers.gmarkers[urn].show() : markers.gmarkers[urn].hide();
	  }
	}, 
	
	refresh: function( e ) {
	  google.maps.Log.write( "Refreshing sidebar: " + sidebar.target );
	  var list = document.getElementById(sidebar.target);
	  list.innerHTML = sidebar.contents;
	  
	  // instantiate the list
	  checkmenu = new CheckTree('checkmenu');		
	  checkmenu.init();
	  
	  return false;
	},
	setContent: function( html ) {
	  var content = document.getElementById(sidebar.target);
	  content.innerHTML = html;
	  return false;
	}
}
