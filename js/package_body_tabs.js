// Javascript to enable link to tab
$(function() {
  var url = document.location.toString();
  if (url.match('#')) {
      $('.nav-tabs a[href="#'+url.split('#')[1]+'"]').tab('show') ;
  }

  // Change hash for page-reload
  $('.nav-tabs a').on('shown', function (e) {
      window.location.hash = e.target.hash;
  });

  $("a[href^='#']").on("click", function(e) {
     e.preventDefault();
     history.pushState({}, "", this.href);
  });

});
