/**
 * Storage API Test - Background Script
 * Tests chrome.storage.local and chrome.storage.session APIs
 */

console.log('💾 [Storage Test] Background script starting...');

let testResults = {
  local: {},
  session: {},
  onChanged: {}
};

// Test 1: chrome.storage.local.set()
async function testLocalSet() {
  console.log('✅ Test 1: chrome.storage.local.set()');
  
  return new Promise((resolve) => {
    const testData = {
      simpleString: 'Hello World',
      simpleNumber: 42,
      simpleBoolean: true,
      simpleArray: [1, 2, 3, 4, 5],
      simpleObject: { name: 'Test', nested: { value: 123 } },
      timestamp: Date.now()
    };
    
    chrome.storage.local.set(testData, () => {
      if (chrome.runtime.lastError) {
        console.error('   ❌ FAIL:', chrome.runtime.lastError.message);
        testResults.local.set = false;
        resolve(false);
      } else {
        console.log('   ✅ PASS: Data saved successfully');
        testResults.local.set = true;
        resolve(true);
      }
    });
  });
}

// Test 2: chrome.storage.local.get()
async function testLocalGet() {
  console.log('✅ Test 2: chrome.storage.local.get()');
  
  return new Promise((resolve) => {
    chrome.storage.local.get(
      ['simpleString', 'simpleNumber', 'simpleBoolean', 'simpleArray', 'simpleObject'],
      (result) => {
        if (chrome.runtime.lastError) {
          console.error('   ❌ FAIL:', chrome.runtime.lastError.message);
          testResults.local.get = false;
          resolve(false);
        } else {
          console.log('   Retrieved data:', result);
          
          // Verify data integrity
          const valid = 
            result.simpleString === 'Hello World' &&
            result.simpleNumber === 42 &&
            result.simpleBoolean === true &&
            Array.isArray(result.simpleArray) &&
            result.simpleArray.length === 5 &&
            result.simpleObject.name === 'Test';
          
          if (valid) {
            console.log('   ✅ PASS: Data retrieved correctly');
            testResults.local.get = true;
            resolve(true);
          } else {
            console.error('   ❌ FAIL: Data integrity check failed');
            testResults.local.get = false;
            resolve(false);
          }
        }
      }
    );
  });
}

// Test 3: chrome.storage.local.get() with null (get all)
async function testLocalGetAll() {
  console.log('✅ Test 3: chrome.storage.local.get(null) - Get all data');
  
  return new Promise((resolve) => {
    chrome.storage.local.get(null, (result) => {
      if (chrome.runtime.lastError) {
        console.error('   ❌ FAIL:', chrome.runtime.lastError.message);
        testResults.local.getAll = false;
        resolve(false);
      } else {
        console.log('   All data:', Object.keys(result));
        console.log('   Item count:', Object.keys(result).length);
        
        if (Object.keys(result).length >= 5) {
          console.log('   ✅ PASS: Retrieved all data');
          testResults.local.getAll = true;
          resolve(true);
        } else {
          console.error('   ❌ FAIL: Not all data retrieved');
          testResults.local.getAll = false;
          resolve(false);
        }
      }
    });
  });
}

// Test 4: chrome.storage.local.getBytesInUse()
async function testLocalBytesInUse() {
  console.log('✅ Test 4: chrome.storage.local.getBytesInUse()');
  
  return new Promise((resolve) => {
    chrome.storage.local.getBytesInUse(null, (bytes) => {
      if (chrome.runtime.lastError) {
        console.error('   ❌ FAIL:', chrome.runtime.lastError.message);
        testResults.local.getBytesInUse = false;
        resolve(false);
      } else {
        console.log('   Storage size:', bytes, 'bytes');
        
        if (bytes > 0) {
          console.log('   ✅ PASS: getBytesInUse() works');
          testResults.local.getBytesInUse = true;
          resolve(true);
        } else {
          console.warn('   ⚠️  WARN: Bytes in use is 0 (may not be implemented)');
          testResults.local.getBytesInUse = 'partial';
          resolve(true);
        }
      }
    });
  });
}

// Test 5: chrome.storage.local.remove()
async function testLocalRemove() {
  console.log('✅ Test 5: chrome.storage.local.remove()');
  
  return new Promise((resolve) => {
    chrome.storage.local.remove(['simpleBoolean'], () => {
      if (chrome.runtime.lastError) {
        console.error('   ❌ FAIL:', chrome.runtime.lastError.message);
        testResults.local.remove = false;
        resolve(false);
      } else {
        // Verify it was removed
        chrome.storage.local.get(['simpleBoolean'], (result) => {
          if (result.simpleBoolean === undefined) {
            console.log('   ✅ PASS: Item removed successfully');
            testResults.local.remove = true;
            resolve(true);
          } else {
            console.error('   ❌ FAIL: Item still exists after remove');
            testResults.local.remove = false;
            resolve(false);
          }
        });
      }
    });
  });
}

// Test 6: chrome.storage.session.set()
async function testSessionSet() {
  console.log('✅ Test 6: chrome.storage.session.set()');
  
  return new Promise((resolve) => {
    const sessionData = {
      sessionKey: 'Session Value',
      sessionNumber: 999,
      sessionTimestamp: Date.now()
    };
    
    chrome.storage.session.set(sessionData, () => {
      if (chrome.runtime.lastError) {
        console.error('   ❌ FAIL:', chrome.runtime.lastError.message);
        testResults.session.set = false;
        resolve(false);
      } else {
        console.log('   ✅ PASS: Session data saved');
        testResults.session.set = true;
        resolve(true);
      }
    });
  });
}

// Test 7: chrome.storage.session.get()
async function testSessionGet() {
  console.log('✅ Test 7: chrome.storage.session.get()');
  
  return new Promise((resolve) => {
    chrome.storage.session.get(['sessionKey', 'sessionNumber'], (result) => {
      if (chrome.runtime.lastError) {
        console.error('   ❌ FAIL:', chrome.runtime.lastError.message);
        testResults.session.get = false;
        resolve(false);
      } else {
        console.log('   Retrieved session data:', result);
        
        if (result.sessionKey === 'Session Value' && result.sessionNumber === 999) {
          console.log('   ✅ PASS: Session data retrieved correctly');
          testResults.session.get = true;
          resolve(true);
        } else {
          console.error('   ❌ FAIL: Session data mismatch');
          testResults.session.get = false;
          resolve(false);
        }
      }
    });
  });
}

// Test 8: chrome.storage.onChanged listener
function testOnChangedListener() {
  console.log('✅ Test 8: chrome.storage.onChanged listener');
  
  chrome.storage.onChanged.addListener((changes, areaName) => {
    console.log('   📥 Storage change detected:');
    console.log('      Area:', areaName);
    console.log('      Changes:', changes);
    
    testResults.onChanged.listener = true;
    
    for (let key in changes) {
      const change = changes[key];
      console.log(`      ${key}: ${JSON.stringify(change.oldValue)} → ${JSON.stringify(change.newValue)}`);
    }
  });
  
  console.log('   ✅ onChanged listener registered');
  testResults.onChanged.registered = true;
}

// Test 9: Trigger onChanged event
async function testOnChangedTrigger() {
  console.log('✅ Test 9: Trigger onChanged event');
  
  return new Promise((resolve) => {
    testResults.onChanged.listener = false;
    
    // Make a change to trigger the event
    chrome.storage.local.set({ testChange: 'trigger-value' }, () => {
      // Wait a bit for the event to fire
      setTimeout(() => {
        if (testResults.onChanged.listener) {
          console.log('   ✅ PASS: onChanged event fired');
          resolve(true);
        } else {
          console.error('   ❌ FAIL: onChanged event did not fire');
          resolve(false);
        }
      }, 500);
    });
  });
}

// Test 10: Large data storage
async function testLargeData() {
  console.log('✅ Test 10: Large data storage');
  
  return new Promise((resolve) => {
    // Create ~100KB of data
    const largeString = 'x'.repeat(100000);
    const largeArray = Array.from({ length: 1000 }, (_, i) => ({ id: i, data: 'item-' + i }));
    
    chrome.storage.local.set({ largeString, largeArray }, () => {
      if (chrome.runtime.lastError) {
        console.error('   ❌ FAIL:', chrome.runtime.lastError.message);
        testResults.local.largeData = false;
        resolve(false);
      } else {
        // Verify retrieval
        chrome.storage.local.get(['largeString', 'largeArray'], (result) => {
          if (result.largeString.length === 100000 && result.largeArray.length === 1000) {
            console.log('   ✅ PASS: Large data stored and retrieved');
            testResults.local.largeData = true;
            resolve(true);
          } else {
            console.error('   ❌ FAIL: Large data integrity check failed');
            testResults.local.largeData = false;
            resolve(false);
          }
        });
      }
    });
  });
}

// Test 11: chrome.storage.local.clear()
async function testLocalClear() {
  console.log('✅ Test 11: chrome.storage.local.clear()');
  
  return new Promise((resolve) => {
    chrome.storage.local.clear(() => {
      if (chrome.runtime.lastError) {
        console.error('   ❌ FAIL:', chrome.runtime.lastError.message);
        testResults.local.clear = false;
        resolve(false);
      } else {
        // Verify it's empty
        chrome.storage.local.get(null, (result) => {
          if (Object.keys(result).length === 0) {
            console.log('   ✅ PASS: Storage cleared successfully');
            testResults.local.clear = true;
            resolve(true);
          } else {
            console.error('   ❌ FAIL: Storage not empty after clear');
            console.error('      Remaining keys:', Object.keys(result));
            testResults.local.clear = false;
            resolve(false);
          }
        });
      }
    });
  });
}

// Run all tests
async function runAllTests() {
  console.log('\n=== STORAGE API TEST SUITE ===\n');
  
  // Register onChanged listener first
  testOnChangedListener();
  
  // Run tests sequentially
  await testLocalSet();
  await testLocalGet();
  await testLocalGetAll();
  await testLocalBytesInUse();
  await testLocalRemove();
  await testSessionSet();
  await testSessionGet();
  await testOnChangedTrigger();
  await testLargeData();
  await testLocalClear();
  
  console.log('\n=== TEST SUITE COMPLETE ===\n');
  console.log('Results:', testResults);
  
  // Calculate success rate
  const allTests = [];
  for (let category in testResults) {
    for (let test in testResults[category]) {
      allTests.push(testResults[category][test]);
    }
  }
  
  const passed = allTests.filter(r => r === true).length;
  const total = allTests.length;
  const percentage = ((passed / total) * 100).toFixed(1);
  
  console.log(`\n📊 Success Rate: ${passed}/${total} (${percentage}%)\n`);
}

// Start tests
runAllTests();

console.log('💾 [Storage Test] Background script ready');

