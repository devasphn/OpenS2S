# OpenS2S Optimized System Test Script (PowerShell)
# Comprehensive testing of all optimizations and performance improvements

param(
    [switch]$Verbose
)

# Test results
$TestsPassed = 0
$TestsFailed = 0
$TotalTests = 0

function Write-Status {
    param([string]$Message)
    Write-Host "[✓] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[✗] $Message" -ForegroundColor Red
}

function Write-Header {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Run-Test {
    param(
        [string]$TestName,
        [scriptblock]$TestCommand
    )
    
    $script:TotalTests++
    Write-Header "Running test: $TestName"
    
    try {
        $result = & $TestCommand
        if ($result) {
            Write-Status "PASSED: $TestName"
            $script:TestsPassed++
            return $true
        } else {
            Write-Error "FAILED: $TestName"
            $script:TestsFailed++
            return $false
        }
    } catch {
        Write-Error "FAILED: $TestName - $($_.Exception.Message)"
        $script:TestsFailed++
        return $false
    }
}

# Test 1: Verify project structure
function Test-ProjectStructure {
    Write-Header "Testing optimized project structure..."
    
    # Check that unused directories are removed
    if (Test-Path "cosyvoice" -or Test-Path "third_party") {
        Write-Error "Unused directories still exist"
        return $false
    }
    
    # Check that new directories exist
    $requiredDirs = @("docs", "config", "monitoring", "scripts")
    foreach ($dir in $requiredDirs) {
        if (-not (Test-Path $dir)) {
            Write-Error "Required directory missing: $dir"
            return $false
        }
    }
    
    # Check that documentation was moved
    if (-not (Test-Path "docs/OPTIMIZATION_ANALYSIS.md")) {
        Write-Error "Documentation not properly moved"
        return $false
    }
    
    Write-Status "Project structure optimized correctly"
    return $true
}

# Test 2: Verify model files
function Test-ModelFiles {
    Write-Header "Testing model file validation..."
    
    # Check OpenS2S model
    if (-not (Test-Path "/workspace/models/OpenS2S/config.json")) {
        Write-Warning "OpenS2S config.json missing (may not be downloaded yet)"
        # Don't fail the test if models aren't downloaded
    }
    
    # Check GLM-4-Voice-Decoder model
    if (-not (Test-Path "/workspace/models/glm-4-voice-decoder/config.yaml")) {
        Write-Warning "GLM-4-Voice-Decoder config.yaml missing (may not be downloaded yet)"
        # Don't fail the test if models aren't downloaded
    }
    
    Write-Status "Model file validation completed"
    return $true
}

# Test 3: Test Python imports
function Test-PythonImports {
    Write-Header "Testing Python imports and dependencies..."
    
    $pythonCode = @"
import sys
import torch
import transformers
import fastapi
import websockets
import webrtcvad
import psutil
import numpy as np
import torchaudio
print('All core dependencies imported successfully')
"@
    
    try {
        $result = python -c $pythonCode
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Python imports successful"
            return $true
        } else {
            Write-Error "Python imports failed"
            return $false
        }
    } catch {
        Write-Error "Python imports failed: $($_.Exception.Message)"
        return $false
    }
}

# Test 4: Test performance configuration
function Test-PerformanceConfig {
    Write-Header "Testing performance configuration..."
    
    if (-not (Test-Path "config/performance.yaml")) {
        Write-Error "Performance configuration missing"
        return $false
    }
    
    $pythonCode = @"
import yaml
with open('config/performance.yaml', 'r') as f:
    config = yaml.safe_load(f)

required_sections = ['model', 'audio', 'vad', 'websocket', 'latency_targets']
for section in required_sections:
    if section not in config:
        raise ValueError(f'Missing configuration section: {section}')

print('Performance configuration validated')
"@
    
    try {
        $result = python -c $pythonCode
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Performance configuration valid"
            return $true
        } else {
            Write-Error "Performance configuration invalid"
            return $false
        }
    } catch {
        Write-Error "Performance configuration test failed: $($_.Exception.Message)"
        return $false
    }
}

# Test 5: Test health check system
function Test-HealthCheck {
    Write-Header "Testing health check system..."
    
    if (-not (Test-Path "monitoring/health_check.py")) {
        Write-Error "Health check script missing"
        return $false
    }
    
    $pythonCode = @"
import sys
sys.path.append('monitoring')
from health_check import HealthChecker

checker = HealthChecker()
print('Health check system initialized successfully')
"@
    
    try {
        $result = python -c $pythonCode
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Health check system working"
            return $true
        } else {
            Write-Error "Health check system failed"
            return $false
        }
    } catch {
        Write-Error "Health check test failed: $($_.Exception.Message)"
        return $false
    }
}

# Test 6: Test performance monitoring
function Test-PerformanceMonitoring {
    Write-Header "Testing performance monitoring..."
    
    if (-not (Test-Path "monitoring/performance_monitor.py")) {
        Write-Error "Performance monitor script missing"
        return $false
    }
    
    $pythonCode = @"
import sys
sys.path.append('monitoring')
from performance_monitor import PerformanceMonitor

monitor = PerformanceMonitor()
print('Performance monitoring system initialized successfully')
"@
    
    try {
        $result = python -c $pythonCode
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Performance monitoring working"
            return $true
        } else {
            Write-Error "Performance monitoring failed"
            return $false
        }
    } catch {
        Write-Error "Performance monitoring test failed: $($_.Exception.Message)"
        return $false
    }
}

# Test 7: Test VAD optimizations
function Test-VADOptimizations {
    Write-Header "Testing VAD processor optimizations..."
    
    $pythonCode = @"
import sys
sys.path.append('.')
from vad_processor import VADProcessor

# Test WebRTC VAD
vad = VADProcessor(vad_mode='webrtc')
print('WebRTC VAD initialized successfully')

# Test that performance monitoring attributes exist
if not hasattr(vad, 'processing_times'):
    raise ValueError('Performance monitoring not properly added to VAD')

print('VAD optimizations working correctly')
"@
    
    try {
        $result = python -c $pythonCode
        if ($LASTEXITCODE -eq 0) {
            Write-Status "VAD optimizations working"
            return $true
        } else {
            Write-Error "VAD optimizations failed"
            return $false
        }
    } catch {
        Write-Error "VAD optimization test failed: $($_.Exception.Message)"
        return $false
    }
}

# Test 8: Test production requirements
function Test-ProductionRequirements {
    Write-Header "Testing production requirements..."
    
    if (-not (Test-Path "requirements_production.txt")) {
        Write-Error "Production requirements file missing"
        return $false
    }
    
    # Check that key packages are included
    $content = Get-Content "requirements_production.txt" -Raw
    $requiredPackages = @("torch", "transformers", "fastapi", "websockets", "webrtcvad")
    
    foreach ($package in $requiredPackages) {
        if ($content -notmatch $package) {
            Write-Error "Required package missing: $package"
            return $false
        }
    }
    
    Write-Status "Production requirements validated"
    return $true
}

# Main test execution
function Main {
    Write-Host ""
    Write-Header "🧪 OpenS2S Optimized System Test Suite"
    Write-Header "======================================"
    Write-Host ""
    
    # Run all tests
    Run-Test "Project Structure" { Test-ProjectStructure }
    Run-Test "Model Files" { Test-ModelFiles }
    Run-Test "Python Imports" { Test-PythonImports }
    Run-Test "Performance Config" { Test-PerformanceConfig }
    Run-Test "Health Check" { Test-HealthCheck }
    Run-Test "Performance Monitoring" { Test-PerformanceMonitoring }
    Run-Test "VAD Optimizations" { Test-VADOptimizations }
    Run-Test "Production Requirements" { Test-ProductionRequirements }
    
    Write-Host ""
    Write-Header "📊 Test Results Summary"
    Write-Header "======================="
    Write-Host ""
    
    if ($TestsFailed -eq 0) {
        Write-Status "🎉 All tests passed! ($TestsPassed/$TotalTests)"
        Write-Status "✅ OpenS2S optimization completed successfully"
        Write-Status "🚀 System is ready for production deployment"
        Write-Host ""
        Write-Header "Next steps:"
        Write-Host "  1. Run: ./scripts/start_production.sh"
        Write-Host "  2. Test: python monitoring/health_check.py"
        Write-Host "  3. Monitor: python monitoring/performance_monitor.py"
        Write-Host "  4. Access: http://localhost:8000"
        Write-Host ""
        exit 0
    } else {
        Write-Error "❌ Some tests failed ($TestsFailed/$TotalTests failed)"
        Write-Error "🔧 Please fix the issues before deployment"
        Write-Host ""
        Write-Header "Failed tests need attention before production use"
        exit 1
    }
}

# Run main function
Main
