// Javascript to enable link to tab
$(function() {
  var url = document.location.toString();
  if (url.match('#')) {
      var href = '#' + url.split('#')[1];
      $('.nav-tabs a').filter(function() { return $(this).attr('href') === href; })
        .each(function() { bootstrap.Tab.getOrCreateInstance(this).show(); });
  }

  // Update the URL so a reload returns to the same tab
  $("a[href^='#']").on("click", function(e) {
     e.preventDefault();
     history.pushState({}, "", this.href);
  });

});
