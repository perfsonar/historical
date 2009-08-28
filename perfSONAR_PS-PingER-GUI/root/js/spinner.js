 Ajax.Responders.register({
     onCreate: function() {
        if (Ajax.activeRequestCount === 1) {
           $('spinner').show();
        }
    },
    onComplete: function() {
        if (Ajax.activeRequestCount === 0) {
           $('spinner').hide();
        }
    },
   }); 
