#!/bin/bash

# Verification script for OpenS2S Real-time Setup
# Run this to check if all required files are present

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo "🔍 OpenS2S Real-time Setup Verification"
echo "========================================"

# Check current directory
print_header "Checking current directory: $(pwd)"

# Check original OpenS2S files
echo ""
print_header "Checking original OpenS2S files..."

required_original_files=(
    "controller.py"
    "model_worker.py"
    "web_demo.py"
    "requirements.txt"
    "src/modeling_omnispeech.py"
    "src/constants.py"
    "flow_inference.py"
)

missing_original=0
for file in "${required_original_files[@]}"; do
    if [ -f "$file" ]; then
        print_status "$file"
    else
        print_error "$file - MISSING"
        missing_original=$((missing_original + 1))
    fi
done

# Check real-time streaming files
echo ""
print_header "Checking real-time streaming files..."

required_realtime_files=(
    "runpod_setup.sh"
    "start_realtime_services.sh"
    "vad_processor.py"
    "realtime_server.py"
    "realtime_client.html"
    "web_interface.py"
    "performance_config.py"
    "verify_setup.sh"
    "REALTIME_SETUP_GUIDE.md"
    "requirements_fixed.txt"
    "install_dependencies.sh"
    "DEPENDENCY_FIX_GUIDE.md"
    "download_models_manual.sh"
    "model_downloader.py"
    "verify_models.sh"
    "cleanup_models.sh"
)

missing_realtime=0
for file in "${required_realtime_files[@]}"; do
    if [ -f "$file" ]; then
        print_status "$file"
    else
        print_error "$file - MISSING"
        missing_realtime=$((missing_realtime + 1))
    fi
done

# Check script permissions
echo ""
print_header "Checking script permissions..."

script_files=(
    "runpod_setup.sh"
    "start_realtime_services.sh"
    "verify_setup.sh"
)

for script in "${script_files[@]}"; do
    if [ -f "$script" ]; then
        if [ -x "$script" ]; then
            print_status "$script - executable"
        else
            print_warning "$script - not executable (run: chmod +x $script)"
        fi
    fi
done

# Check Python environment
echo ""
print_header "Checking Python environment..."

if command -v python &> /dev/null; then
    python_version=$(python --version 2>&1)
    print_status "Python available: $python_version"
else
    print_error "Python not found"
fi

if command -v pip &> /dev/null; then
    pip_version=$(pip --version 2>&1)
    print_status "Pip available: $pip_version"
else
    print_error "Pip not found"
fi

# Check if models directory exists
echo ""
print_header "Checking model directories..."

if [ -d "/workspace/models" ]; then
    print_status "Models directory exists: /workspace/models"
    
    if [ -d "/workspace/models/OpenS2S" ]; then
        print_status "OpenS2S model directory found"
        model_size=$(du -sh /workspace/models/OpenS2S 2>/dev/null | cut -f1 || echo "unknown")
        print_status "OpenS2S model size: $model_size"
    else
        print_warning "OpenS2S model not found (will be downloaded during setup)"
    fi
    
    if [ -d "/workspace/models/glm-4-voice-decoder" ]; then
        print_status "GLM-4-Voice-Decoder directory found"
        decoder_size=$(du -sh /workspace/models/glm-4-voice-decoder 2>/dev/null | cut -f1 || echo "unknown")
        print_status "GLM-4-Voice-Decoder size: $decoder_size"
    else
        print_warning "GLM-4-Voice-Decoder not found (will be downloaded during setup)"
    fi
else
    print_warning "Models directory not found (will be created during setup)"
fi

# Summary
echo ""
print_header "Verification Summary"
echo "===================="

if [ $missing_original -eq 0 ]; then
    print_status "All original OpenS2S files present"
else
    print_error "$missing_original original OpenS2S files missing"
fi

if [ $missing_realtime -eq 0 ]; then
    print_status "All real-time streaming files present"
else
    print_error "$missing_realtime real-time streaming files missing"
fi

total_missing=$((missing_original + missing_realtime))

if [ $total_missing -eq 0 ]; then
    echo ""
    print_status "✅ Setup verification PASSED!"
    echo ""
    print_header "Recommended installation approach:"
    echo "1. Make scripts executable: chmod +x *.sh"
    echo "2. Install dependencies (conflict-free): ./install_dependencies.sh"
    echo "3. Run setup: ./runpod_setup.sh"
    echo "4. Start services: ./start_realtime_services.sh"
    echo "5. Access interface: http://your-runpod-url:8000"
    echo ""
    print_header "Alternative if you encounter dependency conflicts:"
    echo "1. Read the guide: cat DEPENDENCY_FIX_GUIDE.md"
    echo "2. Use fixed requirements: pip install -r requirements_fixed.txt"
    echo "3. Continue with setup: ./runpod_setup.sh"
else
    echo ""
    print_error "❌ Setup verification FAILED!"
    print_error "Missing $total_missing files total"
    echo ""
    print_header "Please ensure all files are present before proceeding."
    exit 1
fi
