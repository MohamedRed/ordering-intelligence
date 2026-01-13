// Firebase Cloud Messaging service worker for Flutter web
importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAyva47VFazHoIHMkQVJ7j9_preZIyFlvI',
  appId: '1:230152279015:web:dfda8c675b6dafab8c2342',
  messagingSenderId: '230152279015',
  projectId: 'ordering-intelligence',
});

const messaging = firebase.messaging();

// Optional: handle background messages
messaging.onBackgroundMessage((payload) => {
  const notificationTitle = payload.notification?.title || 'New notification';
  const notificationOptions = {
    body: payload.notification?.body,
    data: payload.data,
  };
  self.registration.showNotification(notificationTitle, notificationOptions);
});
