import { withPluginApi } from 'discourse/lib/plugin-api';

function initialize(api) {
  const messageBus = api.container.lookup('message-bus:main');
  const currentUser = api.getCurrentUser();

  if (messageBus && currentUser) {
    messageBus.subscribe(`/new_user_narrative`, payload => {
      if (payload && payload.keyboard_shortcuts) {
        setTimeout(() => {
          if (payload.keyboard_shortcuts === 'hide') {
            $(".reply, .create").hide();
          } else {
            $(".reply, .create").show();
          }
        }, 3000);
      }
    });
  }
}

export default {
  name: "new-user-narratve",

  initialize() {
    withPluginApi('0.5', initialize);
  }
};
