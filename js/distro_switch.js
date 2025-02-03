function setupDistroSwitch(default_distro) {
  $('#distro-switch label').click(function (e) {
    console.log(e.target)
    // get the distro and set the cookie
    var distro = $('#'+e.target.id).attr('data');
    console.log('selecting distro: '+distro)

    if(distro) {
      $('.distro').not('.distro-'+distro).hide(0, function(){
        $('.distro-'+distro).fadeIn('fast');
      });
      $('#older-distro-button').removeClass("active");
      $('.older-distro-option').removeClass("active");
      $('#older-label').text('Older');

      $.cookie('rosdistro', distro, {path: '/'});
      window.open('#'+distro,'_self');
    }
  })

  $('#distro-switch a').click(function (e) {
    // get the distro and set the cookie
    var distro = $('#'+e.target.id).attr('data');
    $.cookie('rosdistro',distro, {path: '/'});
    console.log('selecting distro: '+distro)

    //$(this).tab('show');
    $('.distro').not('.distro-'+distro).hide(0, function(){
      $('.distro-'+distro).fadeIn('fast');
    });

    console.log('#'+distro+'-option');
    $('.distro-button').removeClass("active");
    console.log($('.older-distro-option').not('#'+distro+'-option'))
    $('.older-distro-option').not('#'+distro+'-option').removeClass("active");
    $('#older-distro-button').addClass("active");
    $('#'+distro+'-option').addClass('active');

    $('#older-label').text(distro);
    window.open('#'+distro,'_self');
  });

  // set the distro based on cookie
  var distro = $.cookie('rosdistro');
  console.log("preferring "+distro+" distro");

  var url = document.location.toString();
  if (url.match('#')) {
    distro = url.split('#')[1].split('-')[0];
    console.log("overriding via anchor "+distro+" distro");
  }

  if(typeof distro == 'undefined') {
    distro = default_distro;
  }

  $('.distro').not('.distro-'+distro).hide(0);
  $('.distro-'+distro).show(0);
  $('#'+distro+'-option').addClass('active');
  $('#'+distro+'-button').trigger("click");
  return distro;
}
