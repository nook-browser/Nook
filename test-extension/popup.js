// Clipboard API Test Extension for Nook
// Tests navigator.clipboard.writeText() and readText() implementation

console.log('[Clipboard Test] Extension loaded');

// Test state
let testResults = {
  apiDetection: false,
  write: false,
  read: false,
  roundTrip: false
};

// Initialize on load
document.addEventListener('DOMContentLoaded', () => {
  console.log('[Clipboard Test] DOM loaded, initializing...');
  
  // Check API availability
  checkAPIAvailability();
  
  // Set up button handlers
  document.getElementById('writeBtn').addEventListener('click', testWrite);
  document.getElementById('readBtn').addEventListener('click', testRead);
  document.getElementById('roundTripBtn').addEventListener('click', testRoundTrip);
  document.getElementById('runAllBtn').addEventListener('click', runAllTests);
  
  console.log('[Clipboard Test] Event handlers registered');
});

// Check if clipboard API is available
function checkAPIAvailability() {
  console.log('[Clipboard Test] Checking API availability...');
  
  const clipboardExists = typeof navigator.clipboard !== 'undefined';
  const writeTextExists = clipboardExists && typeof navigator.clipboard.writeText === 'function';
  const readTextExists = clipboardExists && typeof navigator.clipboard.readText === 'function';
  
  // Update UI
  updateStatusIndicator('clipboardExists', clipboardExists);
  updateStatusIndicator('writeTextExists', writeTextExists);
  updateStatusIndicator('readTextExists', readTextExists);
  
  testResults.apiDetection = clipboardExists && writeTextExists && readTextExists;
  
  console.log('[Clipboard Test] API Detection Results:', {
    clipboardExists,
    writeTextExists,
    readTextExists
  });
}

function updateStatusIndicator(elementId, isAvailable) {
  const element = document.getElementById(elementId);
  const indicator = element.previousElementSibling;
  
  if (isAvailable) {
    element.textContent = '✅ Available';
    indicator.className = 'status-indicator pass';
  } else {
    element.textContent = '❌ Not Available';
    indicator.className = 'status-indicator fail';
  }
}

// Test: Write to clipboard
async function testWrite() {
  console.log('[Clipboard Test] Starting write test...');
  
  const input = document.getElementById('writeInput');
  const resultDiv = document.getElementById('writeResult');
  const text = input.value;
  
  if (!text) {
    showResult(resultDiv, 'error', '❌ Please enter text to copy');
    return;
  }
  
  try {
    console.log(`[Clipboard Test] Writing ${text.length} characters to clipboard`);
    
    const startTime = performance.now();
    await navigator.clipboard.writeText(text);
    const duration = (performance.now() - startTime).toFixed(2);
    
    console.log(`[Clipboard Test] Write successful in ${duration}ms`);
    showResult(resultDiv, 'success', `✅ Copied ${text.length} characters to clipboard (${duration}ms)`);
    testResults.write = true;
    
  } catch (error) {
    console.error('[Clipboard Test] Write error:', error);
    showResult(resultDiv, 'error', `❌ Write failed: ${error.message}`);
    testResults.write = false;
  }
}

// Test: Read from clipboard
async function testRead() {
  console.log('[Clipboard Test] Starting read test...');
  
  const output = document.getElementById('readOutput');
  const resultDiv = document.getElementById('readResult');
  
  try {
    const startTime = performance.now();
    const text = await navigator.clipboard.readText();
    const duration = (performance.now() - startTime).toFixed(2);
    
    console.log(`[Clipboard Test] Read successful: ${text.length} characters in ${duration}ms`);
    
    output.value = text;
    
    if (text.length === 0) {
      showResult(resultDiv, 'info', `ℹ️ Clipboard is empty (${duration}ms)`);
    } else {
      showResult(resultDiv, 'success', `✅ Read ${text.length} characters from clipboard (${duration}ms)`);
    }
    
    testResults.read = true;
    
  } catch (error) {
    console.error('[Clipboard Test] Read error:', error);
    output.value = '';
    showResult(resultDiv, 'error', `❌ Read failed: ${error.message}`);
    testResults.read = false;
  }
}

// Test: Round trip (write then read)
async function testRoundTrip() {
  console.log('[Clipboard Test] Starting round trip test...');
  
  const resultDiv = document.getElementById('roundTripResult');
  const testData = `Round Trip Test ${Date.now()} 🔄`;
  
  try {
    // Step 1: Write
    console.log(`[Clipboard Test] Round trip - writing: "${testData}"`);
    await navigator.clipboard.writeText(testData);
    
    // Small delay to ensure write completes
    await new Promise(resolve => setTimeout(resolve, 100));
    
    // Step 2: Read
    console.log('[Clipboard Test] Round trip - reading back...');
    const readBack = await navigator.clipboard.readText();
    
    // Step 3: Verify
    console.log(`[Clipboard Test] Round trip - read back: "${readBack}"`);
    
    if (readBack === testData) {
      console.log('[Clipboard Test] Round trip PASSED ✅');
      showResult(resultDiv, 'success', '✅ Round trip test PASSED! Data integrity verified.');
      testResults.roundTrip = true;
    } else {
      console.error('[Clipboard Test] Round trip FAILED - data mismatch');
      console.error('  Expected:', testData);
      console.error('  Got:', readBack);
      showResult(resultDiv, 'error', `❌ Round trip FAILED! Data mismatch.\nExpected: ${testData}\nGot: ${readBack}`);
      testResults.roundTrip = false;
    }
    
  } catch (error) {
    console.error('[Clipboard Test] Round trip error:', error);
    showResult(resultDiv, 'error', `❌ Round trip failed: ${error.message}`);
    testResults.roundTrip = false;
  }
}

// Run all tests in sequence
async function runAllTests() {
  console.log('[Clipboard Test] Running all tests...');
  
  const button = document.getElementById('runAllBtn');
  button.disabled = true;
  button.textContent = '🧪 Running Tests...';
  
  try {
    // Test 1: API Detection (already done)
    console.log('[Clipboard Test] Test 1/3: API Detection');
    checkAPIAvailability();
    await new Promise(resolve => setTimeout(resolve, 500));
    
    // Test 2: Write
    console.log('[Clipboard Test] Test 2/3: Write Test');
    await testWrite();
    await new Promise(resolve => setTimeout(resolve, 500));
    
    // Test 3: Read
    console.log('[Clipboard Test] Test 3/3: Read Test');
    await testRead();
    await new Promise(resolve => setTimeout(resolve, 500));
    
    // Test 4: Round Trip
    console.log('[Clipboard Test] Test 4/4: Round Trip Test');
    await testRoundTrip();
    
    // Show summary
    const totalTests = 4;
    const passedTests = Object.values(testResults).filter(r => r === true).length;
    
    console.log('[Clipboard Test] Test Summary:', testResults);
    console.log(`[Clipboard Test] ${passedTests}/${totalTests} tests passed`);
    
    alert(`Test Suite Complete!\n\n${passedTests}/${totalTests} tests passed\n\nCheck console for detailed logs.`);
    
  } catch (error) {
    console.error('[Clipboard Test] Test suite error:', error);
    alert(`Test suite failed: ${error.message}`);
  } finally {
    button.disabled = false;
    button.textContent = '🧪 Run All Tests';
  }
}

// Helper: Show result message
function showResult(element, type, message) {
  element.className = `result ${type}`;
  element.textContent = message;
  element.style.display = 'block';
  
  // Auto-hide after 5 seconds for success messages
  if (type === 'success') {
    setTimeout(() => {
      element.style.display = 'none';
    }, 5000);
  }
}

// Log when clipboard API is accessed
console.log('[Clipboard Test] Clipboard API check:', {
  exists: typeof navigator.clipboard !== 'undefined',
  writeText: typeof navigator?.clipboard?.writeText,
  readText: typeof navigator?.clipboard?.readText
});

