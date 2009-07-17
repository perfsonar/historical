 
function filterMAs(name,index) {
      $$('input.bbuttons_filter_ma_selected').each(function(name){
                $(name).removeClassName('bbuttons_filter_ma_selected');
		 
      });
      $('params_table').hide();
      $('get_graph2').removeClassName('bbuttons_filter_ma_selected'); 
      $('get_links').removeClassName('bbuttons_filter_ma_selected');
      $('filter_project' + index).addClassName('bbuttons_filter_ma_selected');
      new Ajax.Updater({ success: 'filtered_ma', failure: 'statusDiv'}, '/gui/filter_links', {
                      parameters: { filter_project : name }
     });
}     

function displayLinks() {
   var params = {};
  
   $('get_graph2').removeClassName('bbuttons_filter_ma_selected'); 
   $('get_links').addClassName('bbuttons_filter_ma_selected');
   ['ma_urls', 'src_regexp', 'dst_regexp', 'filter_project', 'packetsize', 'stored_links', 'select_url'].each(function(name) {
       if($(name)  && $F(name)) {
          this[name] = $F(name);
       }
   }, params); 
   new Ajax.Updater({ success: 'linksdiv', failure: 'statusDiv'}, '/gui/displayLinks', {
                      parameters: params
   }); 
   $('params_table').show();
    
}

function displayGraph() {
   var params = {}; 
   if ($('notice')) {
       $('notice').hide(); 
   }
   $('get_graph2').addClassName('bbuttons_filter_ma_selected');
   ['start_time', 'end_time',  'gmt_offset', 'filter_project',  'gtype', 'upper_rt','gpresent',   'links', 'stored_links'].each(function(name, index) {
       if($(name)) {
          this[name] = $(name).value;
       }
   }, params); 
   new Ajax.Updater({ success: 'graph', failure: 'statusDiv'}, '/gui/displayGraph', {
                      parameters: params
   });
   
  
}

function resetSession() {
   var params = {};
   new Ajax.Updater({ success: 'wrapper', failure: 'statusDiv'}, '/gui/display');
} 
 
