#!/bin/bash

# Model Cleanup Utility for OpenS2S Real-time Streaming
# Use this to clean up partial or corrupted model downloads

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

echo "🧹 OpenS2S Model Cleanup Utility"
echo "================================"

# Function to show model status
show_model_status() {
    local model_name="$1"
    local model_path="$2"
    
    if [ ! -d "$model_path" ]; then
        echo "  Status: NOT DOWNLOADED"
        return
    fi
    
    local dir_size=$(du -sh "$model_path" 2>/dev/null | cut -f1 || echo "unknown")
    local file_count=$(find "$model_path" -type f | wc -l)
    echo "  Status: EXISTS ($dir_size, $file_count files)"
    
    # Check specific files
    if [ "$model_name" = "OpenS2S" ]; then
        local required_files=("config.json" "tokenizer.json" "tokenizer_config.json")
        local missing=0
        
        for file in "${required_files[@]}"; do
            if [ ! -f "$model_path/$file" ]; then
                missing=$((missing + 1))
            fi
        done
        
        if ! ls "$model_path"/*.safetensors 1> /dev/null 2>&1 && ! ls "$model_path"/*.bin 1> /dev/null 2>&1; then
            missing=$((missing + 1))
        fi
        
        if [ $missing -eq 0 ]; then
            echo "  Validation: COMPLETE"
        else
            echo "  Validation: INCOMPLETE ($missing missing files)"
        fi
        
    elif [ "$model_name" = "GLM-4-Voice-Decoder" ]; then
        local required_files=("config.json" "flow.pt" "hift.pt")
        local missing=0
        
        for file in "${required_files[@]}"; do
            if [ ! -f "$model_path/$file" ]; then
                missing=$((missing + 1))
            elif [[ "$file" == *.pt ]]; then
                local file_size=$(stat -c%s "$model_path/$file" 2>/dev/null || echo "0")
                if [ "$file_size" -lt 1000000 ]; then
                    missing=$((missing + 1))
                fi
            fi
        done
        
        if [ $missing -eq 0 ]; then
            echo "  Validation: COMPLETE"
        else
            echo "  Validation: INCOMPLETE ($missing missing/invalid files)"
        fi
    fi
}

# Show current status
print_header "Current Model Status:"
echo ""
echo "OpenS2S Model:"
show_model_status "OpenS2S" "/workspace/models/OpenS2S"
echo ""
echo "GLM-4-Voice-Decoder Model:"
show_model_status "GLM-4-Voice-Decoder" "/workspace/models/glm-4-voice-decoder"
echo ""

# Menu for cleanup options
print_header "Cleanup Options:"
echo "1. Clean up OpenS2S model only"
echo "2. Clean up GLM-4-Voice-Decoder model only"
echo "3. Clean up both models (complete reset)"
echo "4. Clean up only incomplete/partial downloads"
echo "5. Exit without changes"
echo ""

read -p "Choose an option (1-5): " choice

case $choice in
    1)
        print_warning "Cleaning up OpenS2S model..."
        if [ -d "/workspace/models/OpenS2S" ]; then
            rm -rf /workspace/models/OpenS2S
            print_status "OpenS2S model removed"
        else
            print_status "OpenS2S model was not present"
        fi
        ;;
    2)
        print_warning "Cleaning up GLM-4-Voice-Decoder model..."
        if [ -d "/workspace/models/glm-4-voice-decoder" ]; then
            rm -rf /workspace/models/glm-4-voice-decoder
            print_status "GLM-4-Voice-Decoder model removed"
        else
            print_status "GLM-4-Voice-Decoder model was not present"
        fi
        ;;
    3)
        print_warning "Cleaning up ALL models..."
        if [ -d "/workspace/models" ]; then
            rm -rf /workspace/models
            mkdir -p /workspace/models
            print_status "All models removed, models directory recreated"
        else
            mkdir -p /workspace/models
            print_status "Models directory created"
        fi
        ;;
    4)
        print_warning "Cleaning up only incomplete downloads..."
        
        # Check OpenS2S
        if [ -d "/workspace/models/OpenS2S" ]; then
            missing_openspeech=0
            required_files=("config.json" "tokenizer.json" "tokenizer_config.json")
            
            for file in "${required_files[@]}"; do
                if [ ! -f "/workspace/models/OpenS2S/$file" ]; then
                    missing_openspeech=$((missing_openspeech + 1))
                fi
            done
            
            if ! ls /workspace/models/OpenS2S/*.safetensors 1> /dev/null 2>&1 && ! ls /workspace/models/OpenS2S/*.bin 1> /dev/null 2>&1; then
                missing_openspeech=$((missing_openspeech + 1))
            fi
            
            if [ $missing_openspeech -gt 0 ]; then
                print_warning "OpenS2S is incomplete, removing..."
                rm -rf /workspace/models/OpenS2S
                print_status "Incomplete OpenS2S model removed"
            else
                print_status "OpenS2S model is complete, keeping"
            fi
        fi
        
        # Check GLM-4-Voice-Decoder
        if [ -d "/workspace/models/glm-4-voice-decoder" ]; then
            missing_glm=0
            required_files=("config.json" "flow.pt" "hift.pt")
            
            for file in "${required_files[@]}"; do
                if [ ! -f "/workspace/models/glm-4-voice-decoder/$file" ]; then
                    missing_glm=$((missing_glm + 1))
                elif [[ "$file" == *.pt ]]; then
                    file_size=$(stat -c%s "/workspace/models/glm-4-voice-decoder/$file" 2>/dev/null || echo "0")
                    if [ "$file_size" -lt 1000000 ]; then
                        missing_glm=$((missing_glm + 1))
                    fi
                fi
            done
            
            if [ $missing_glm -gt 0 ]; then
                print_warning "GLM-4-Voice-Decoder is incomplete, removing..."
                rm -rf /workspace/models/glm-4-voice-decoder
                print_status "Incomplete GLM-4-Voice-Decoder model removed"
            else
                print_status "GLM-4-Voice-Decoder model is complete, keeping"
            fi
        fi
        ;;
    5)
        print_status "No changes made"
        exit 0
        ;;
    *)
        print_error "Invalid option"
        exit 1
        ;;
esac

echo ""
print_header "Cleanup completed!"
print_header "Next steps:"
echo "1. Run model download: ./download_models_manual.sh"
echo "2. Or use Python downloader: python model_downloader.py"
echo "3. Verify models: ./verify_models.sh"
echo "4. Start services: ./start_realtime_services.sh"
