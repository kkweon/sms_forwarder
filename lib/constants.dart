const keywords = [
  'verif', 'code', 'otp', 'passcode', 'pin', 'auth', 'confirm',
];

// Loop / rate-limit detection: if more than loopThreshold messages are
// forwarded within loopWindowMs milliseconds, forwarding is auto-disabled.
const recentForwardsKey = 'recent_forwards';
const loopWindowMs = 60 * 1000; // 60 seconds
const loopThreshold = 5;

const maxLogEntries = 50;
const sendTimeoutSeconds = 30;

// SharedPreferences keys
const prefsForwardingEnabled = 'forwarding_enabled';
const prefsLoopDetected = 'loop_detected';
const prefsDestinationNumbers = 'destination_numbers';
const prefsForwardingLog = 'forwarding_log';
