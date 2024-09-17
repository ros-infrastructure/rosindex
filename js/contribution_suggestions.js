/**
 * Populate one of the tabs of the contribution suggestions
 * list. Called by setupContributeLists() for each
 * of the three list tabs.
 * Used on the repo instance (_layouts/repo_instance.html) page.
 * @param {string} list The name of the list tab (eg "help-wanted".
 * @param {array} items The data (JSON) to populate the list from.
 */
function populateContributeLists(list, response) {
  response.json().then(items => {
    if (response.ok) {
      // Write the html for the list items.
      var html = '<table class="table table-condensed table-striped"><tbody>';
      for (const item of items) {
        html += '<tr><td><a href="' + item['html_url'] + '">#';
        html += item['number'] + '</td><td>' + item['title'] + '</a></td></tr>';
      }
      html += '</tbody>';
      $('.contribute-lists-'+list).each(function() {
        $(this).html(html);
      });
      countText = items.length <= 99 ? items.length : ">99";
    } else {
      countText = "---"
    }
    // Update the number of items in the tab header.
    $('.contribute-lists-'+list+'-count').each(function() {
      $(this).text(countText)
    });
  });
}


/**
 * Populate the three tabs of the contribution suggestions
 * list on this page.
 * Currently only works for github repositories.
 * Used on the repo instance (_layouts/repo_instance.html) page.
 * @param {string} repo_uri The URL of the github repo.
 */
function setupContributeLists(repo_uri) {
  // Expected uri pattern:
  // "https://github.com/<owner>/<repo>[.git]"
  if (!repo_uri.includes("github.com")) {
    return;
  }
  // Target query pattern:
  // "https://api.github.com/repos/<owner>/<repo>/pulls"
  api_uri = repo_uri.replace(/\.git$/, "").replace("github.com", "api.github.com/repos");
  // Populate the three tabs of the contribution
  // suggestions list.
  fetch(api_uri + "/issues?state=open&labels=help%20wanted&per_page=100")
    .then(response => populateContributeLists('help-wanted', response))
    .catch(error => console.error(error));
  fetch(api_uri + "/issues?state=open&labels=good%20first%20issue&per_page=100")
    .then(response => populateContributeLists('good-first-issue', response))
    .catch(error => console.error(error));
  fetch(api_uri + "/pulls?state=open&per_page=100")
    .then(response => populateContributeLists('pull-requests', response))
    .catch(error => console.error(error));
}

/**
 * Enable and execute page anchor links pointing
 * at particular tabs of the contribution suggestion
 * lists.
 * Page anchor links take the form of
 * "r/<repo>/#<distro>-contribute-lists-<list_type>"
 * for example:
 * "r/moveit/#kinetic-contribute-lists-help-wanted".
 * The first part of the anchor (<distro> eg "kinetic")
 * will cause the distro switcher to switch to the
 * correct ROS distro to display.
 * The last part of the anchor (<list_type> eg "help-wanted")
 * will cause the contribution suggestion list
 * to switch to the proper tab.
 * Used on the repo instance (_layouts/repo_instance.html) page.
 */
function setupContributeListTabLinks() {
  var url = document.location.toString();
  if (url.match('#')) {
    $('.nav-tabs a[href="#'+url.split('#')[1]+'"]').tab('show');
  }
  // Change hash for page-reload
  $('.nav-tabs a').on('shown', function (e) {
      window.location.hash = e.target.hash;
  });

  $("a[href^='#']").on("click", function(e) {
     e.preventDefault();
     history.pushState({}, "", this.href);
  });
}


/**
 * Update the numbers of items of contribution
 * suggestiond for each repository.
 * Used on the contribution suggestions page
 * (_layouts/contribution_suggestions.html)
 * @param {string} repo_name The name of the repo.
 * @param {string} repo_uri The URL of the github repo.
 */
function updateContributionSuggestionsCount(repo_name, repo_uri) {
  // Incoming uri format:
  // "https://github.com/<owner>/<repo>/tree/master"
  if (!repo_uri.includes('github.com')) {
    return;
  }
  // Target query pattern:
  // "https://api.github.com/repos/<owner>/<repo>/pulls"
  var details = repo_uri.match(/github\.com\/([^\/]*)\/([^\/]*)/);
  api_uri = 'https://api.github.com/repos/' + details[1] + '/' + details[2];

  fetch(api_uri + '/issues?state=open&labels=help%20wanted&per_page=99')
  .then(response => response.json())
  .then(data => {
    $('.contribute-lists-'+repo_name+' .contribute-lists-help-wanted-count').text(data.length);
  })
  .catch(error => console.error(error));

  fetch(api_uri + '/issues?state=open&labels=good%20first%20issue&per_page=99')
  .then(response => response.json())
  .then(data => {
    $('.contribute-lists-'+repo_name+' .contribute-lists-good-first-issue-count').text(data.length);
  })
  .catch(error => console.error(error));

  fetch(api_uri + "/pulls?state=open&per_page=100")
  .then(response => response.json())
  .then(data => {
    $('.contribute-lists-'+repo_name+' .contribute-lists-pull-requests-count').text(data.length);
  })
  .catch(error => console.error(error));
}


/**
 * Update the numbers of items of contribution
 * suggestiond for each repository.
 * Used on each package page
 * (_includes/package_body.html)
 * @param {string} repo_uri The URL of the github repo.
 */
function updateContributionSuggestionsCountOnPackage(repo_uri) {
  if (!repo_uri.includes("github.com")) {
    return;
  }
  api_uri = repo_uri.replace(/\.git$/, "").replace("github.com", "api.github.com/repos");
  fetch(api_uri + "/issues?state=open&labels=help%20wanted&per_page=100")
    .then(response => response.json())
    .then(data => {
      $('.contribute-lists-help-wanted-count').each(function() {
        $(this).text(data.length);
      });
    })
    .catch(error => console.error(error));
  fetch(api_uri + "/issues?state=open&labels=good%20first%20issue&per_page=100")
    .then(response => response.json())
    .then(data => {
      $('.contribute-lists-good-first-issue-count').each(function() {
        $(this).text(data.length);
      });
    })
    .catch(error => console.error(error));
  fetch(api_uri + "/pulls?state=open&per_page=100")
    .then(response => response.json())
    .then(data => {
      $('.contribute-lists-pull-requests-count').each(function() {
        $(this).text(data.length);
      });
    })
    .catch(error => console.error(error));
}
