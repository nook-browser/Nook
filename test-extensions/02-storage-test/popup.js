/**
 * Storage API Test - Popup Script
 */

console.log('💾 [Storage Test] Popup loaded');

// Update statistics
function updateStats() {
  // Local storage stats
  chrome.storage.local.get(null, (items) => {
    const count = Object.keys(items).length;
    document.getElementById('localCount').textContent = count;
    
    chrome.storage.local.getBytesInUse(null, (bytes) => {
      const kb = (bytes / 1024).toFixed(2);
      document.getElementById('localSize').textContent = `${kb} KB`;
    });
  });
  
  // Session storage stats
  chrome.storage.session.get(null, (items) => {
    const count = Object.keys(items).length;
    document.getElementById('sessionCount').textContent = count;
    
    chrome.storage.session.getBytesInUse(null, (bytes) => {
      const kb = (bytes / 1024).toFixed(2);
      document.getElementById('sessionSize').textContent = `${kb} KB`;
    });
  });
}

// Write to local storage
document.getElementById('writeLocal').addEventListener('click', () => {
  const resultDiv = document.getElementById('localResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Writing data...';
  
  const data = {
    popupTest: 'Hello from popup!',
    timestamp: Date.now(),
    randomNumber: Math.floor(Math.random() * 1000),
    nested: { level1: { level2: { value: 'deep' } } }
  };
  
  chrome.storage.local.set(data, () => {
    if (chrome.runtime.lastError) {
      resultDiv.className = 'result error';
      resultDiv.textContent = `❌ ERROR\n${chrome.runtime.lastError.message}`;
    } else {
      resultDiv.className = 'result success';
      resultDiv.textContent = `✅ SUCCESS\nWrote data:\n${JSON.stringify(data, null, 2)}`;
      updateStats();
    }
  });
});

// Read from local storage
document.getElementById('readLocal').addEventListener('click', () => {
  const resultDiv = document.getElementById('localResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Reading data...';
  
  chrome.storage.local.get(null, (items) => {
    if (chrome.runtime.lastError) {
      resultDiv.className = 'result error';
      resultDiv.textContent = `❌ ERROR\n${chrome.runtime.lastError.message}`;
    } else {
      resultDiv.className = 'result success';
      const itemCount = Object.keys(items).length;
      resultDiv.textContent = `✅ SUCCESS\nFound ${itemCount} items:\n${JSON.stringify(items, null, 2)}`;
    }
  });
});

// Clear local storage
document.getElementById('clearLocal').addEventListener('click', () => {
  if (!confirm('Clear all local storage?')) return;
  
  const resultDiv = document.getElementById('localResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Clearing storage...';
  
  chrome.storage.local.clear(() => {
    if (chrome.runtime.lastError) {
      resultDiv.className = 'result error';
      resultDiv.textContent = `❌ ERROR\n${chrome.runtime.lastError.message}`;
    } else {
      resultDiv.className = 'result success';
      resultDiv.textContent = '✅ Storage cleared successfully';
      updateStats();
    }
  });
});

// Write to session storage
document.getElementById('writeSession').addEventListener('click', () => {
  const resultDiv = document.getElementById('sessionResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Writing session data...';
  
  const data = {
    sessionTest: 'Session from popup',
    sessionTime: Date.now(),
    temporary: 'This will be cleared on browser restart'
  };
  
  chrome.storage.session.set(data, () => {
    if (chrome.runtime.lastError) {
      resultDiv.className = 'result error';
      resultDiv.textContent = `❌ ERROR\n${chrome.runtime.lastError.message}`;
    } else {
      resultDiv.className = 'result success';
      resultDiv.textContent = `✅ SUCCESS\nWrote session data:\n${JSON.stringify(data, null, 2)}`;
      updateStats();
    }
  });
});

// Read from session storage
document.getElementById('readSession').addEventListener('click', () => {
  const resultDiv = document.getElementById('sessionResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Reading session data...';
  
  chrome.storage.session.get(null, (items) => {
    if (chrome.runtime.lastError) {
      resultDiv.className = 'result error';
      resultDiv.textContent = `❌ ERROR\n${chrome.runtime.lastError.message}`;
    } else {
      resultDiv.className = 'result success';
      const itemCount = Object.keys(items).length;
      resultDiv.textContent = `✅ SUCCESS\nFound ${itemCount} session items:\n${JSON.stringify(items, null, 2)}`;
    }
  });
});

// Test large data
document.getElementById('testLarge').addEventListener('click', () => {
  const resultDiv = document.getElementById('advancedResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Testing large data storage...';
  
  // Create ~50KB of data
  const largeData = {
    largeString: 'x'.repeat(50000),
    largeArray: Array.from({ length: 500 }, (_, i) => ({ 
      id: i, 
      name: `Item ${i}`,
      data: 'Lorem ipsum dolor sit amet'
    }))
  };
  
  const startTime = performance.now();
  
  chrome.storage.local.set(largeData, () => {
    if (chrome.runtime.lastError) {
      resultDiv.className = 'result error';
      resultDiv.textContent = `❌ ERROR\n${chrome.runtime.lastError.message}`;
    } else {
      chrome.storage.local.get(['largeString', 'largeArray'], (items) => {
        const endTime = performance.now();
        const duration = (endTime - startTime).toFixed(2);
        
        const stringSize = (largeData.largeString.length / 1024).toFixed(2);
        const arraySize = largeData.largeArray.length;
        
        resultDiv.className = 'result success';
        resultDiv.textContent = `✅ SUCCESS\nStored and retrieved:\n- ${stringSize} KB string\n- ${arraySize} array items\nTime: ${duration}ms`;
        updateStats();
      });
    }
  });
});

// Speed test
document.getElementById('testSpeed').addEventListener('click', () => {
  const resultDiv = document.getElementById('advancedResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Running speed test (100 operations)...';
  
  const iterations = 100;
  let completed = 0;
  const startTime = performance.now();
  
  function runIteration(i) {
    const data = { [`speedTest${i}`]: `value-${i}` };
    
    chrome.storage.local.set(data, () => {
      completed++;
      
      if (completed === iterations) {
        const endTime = performance.now();
        const totalTime = (endTime - startTime).toFixed(2);
        const avgTime = (totalTime / iterations).toFixed(2);
        const opsPerSec = (iterations / (totalTime / 1000)).toFixed(2);
        
        resultDiv.className = 'result success';
        resultDiv.textContent = `✅ SUCCESS\nCompleted ${iterations} write operations\nTotal time: ${totalTime}ms\nAvg per op: ${avgTime}ms\nOps/sec: ${opsPerSec}`;
      }
    });
  }
  
  for (let i = 0; i < iterations; i++) {
    runIteration(i);
  }
});

// Refresh stats
document.getElementById('refreshStats').addEventListener('click', updateStats);

// Initialize stats on load
updateStats();

// Listen for storage changes
chrome.storage.onChanged.addListener((changes, areaName) => {
  console.log('💾 Storage changed:', areaName, changes);
  updateStats();
});

console.log('💾 [Storage Test] Popup ready');

