#!/usr/bin/env python3
"""
OpenS2S Model Registration Script
Registers the OmniSpeech model with Transformers AutoConfig and AutoModel
"""

import os
import sys
import json
from pathlib import Path

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent / "src"))

def register_omnispeech_model():
    """Register OmniSpeech model with transformers"""
    try:
        from transformers import AutoConfig, AutoModel
        from src.configuration_omnispeech import OmniSpeechConfig
        from src.modeling_omnispeech import OmniSpeechModel
        
        # Register the configuration and model
        AutoConfig.register("omnispeech", OmniSpeechConfig)
        AutoModel.register(OmniSpeechConfig, OmniSpeechModel)
        
        print("✅ OmniSpeech model registered successfully")
        return True
        
    except Exception as e:
        print(f"❌ Failed to register OmniSpeech model: {e}")
        return False

def create_proper_config_json(model_path: str):
    """Create a proper config.json for OpenS2S model"""
    config_path = Path(model_path) / "config.json"
    
    # Default OpenS2S configuration
    config = {
        "model_type": "omnispeech",
        "architectures": ["OmniSpeechModel"],
        "auto_map": {
            "AutoConfig": "configuration_omnispeech.OmniSpeechConfig",
            "AutoModel": "modeling_omnispeech.OmniSpeechModel"
        },
        "audio_encoder_config": {
            "model_type": "qwen2_audio_encoder",
            "d_model": 1280,
            "encoder_attention_heads": 20,
            "encoder_ffn_dim": 5120,
            "encoder_layerdrop": 0.0,
            "encoder_layers": 32,
            "num_mel_bins": 128,
            "max_source_positions": 1500,
            "scale_embedding": False,
            "activation_function": "gelu"
        },
        "llm_config": {
            "model_type": "qwen2"
        },
        "tts_lm_config": {
            "model_type": "qwen2"
        },
        "conv_kernel_sizes": "5,5",
        "adapter_inner_dim": 512,
        "interleave_strategy": "1:2",
        "torch_dtype": "float16",
        "transformers_version": "4.45.2"
    }
    
    try:
        # Check if config.json already exists
        if config_path.exists():
            print(f"📄 Reading existing config.json from {config_path}")
            with open(config_path, 'r') as f:
                existing_config = json.load(f)
            
            # Check if it has the required fields
            if "model_type" not in existing_config:
                print("⚠️  Missing model_type in existing config, updating...")
                existing_config.update({
                    "model_type": "omnispeech",
                    "architectures": ["OmniSpeechModel"]
                })
                
                # Add auto_map if missing
                if "auto_map" not in existing_config:
                    existing_config["auto_map"] = config["auto_map"]
                
                # Write updated config
                with open(config_path, 'w') as f:
                    json.dump(existing_config, f, indent=2)
                print("✅ Updated existing config.json with model_type")
                return True
            else:
                print("✅ Existing config.json already has model_type")
                return True
        else:
            print(f"📝 Creating new config.json at {config_path}")
            with open(config_path, 'w') as f:
                json.dump(config, f, indent=2)
            print("✅ Created new config.json")
            return True
            
    except Exception as e:
        print(f"❌ Failed to create/update config.json: {e}")
        return False

def fix_openspeech_model(model_path: str = "/workspace/models/OpenS2S"):
    """Complete fix for OpenS2S model loading issues"""
    print(f"🔧 Fixing OpenS2S model at {model_path}")
    
    # Check if model directory exists
    model_dir = Path(model_path)
    if not model_dir.exists():
        print(f"❌ Model directory not found: {model_path}")
        return False
    
    # Register the model
    if not register_omnispeech_model():
        return False
    
    # Create/fix config.json
    if not create_proper_config_json(model_path):
        return False
    
    # Test model loading
    try:
        print("🧪 Testing model loading...")
        from transformers import AutoConfig, AutoTokenizer
        
        # Test config loading
        config = AutoConfig.from_pretrained(model_path, trust_remote_code=True)
        print(f"✅ Config loaded successfully: {config.model_type}")
        
        # Test tokenizer loading
        try:
            tokenizer = AutoTokenizer.from_pretrained(model_path, trust_remote_code=True)
            print(f"✅ Tokenizer loaded successfully: {len(tokenizer)} tokens")
        except Exception as e:
            print(f"⚠️  Tokenizer loading failed (may be normal): {e}")
        
        return True
        
    except Exception as e:
        print(f"❌ Model loading test failed: {e}")
        return False

def main():
    """Main function"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Fix OpenS2S model configuration")
    parser.add_argument("--model-path", default="/workspace/models/OpenS2S",
                       help="Path to OpenS2S model directory")
    
    args = parser.parse_args()
    
    print("🔧 OpenS2S Model Configuration Fix")
    print("==================================")
    
    success = fix_openspeech_model(args.model_path)
    
    if success:
        print("\n✅ OpenS2S model fix completed successfully!")
        print("🎯 Next steps:")
        print("1. Run model verification: ./verify_models.sh")
        print("2. Start services: ./start_realtime_services.sh")
        print("3. Access interface: http://your-runpod-url:8000")
    else:
        print("\n❌ OpenS2S model fix failed!")
        print("💡 Try:")
        print("1. Re-download the model: rm -rf /workspace/models/OpenS2S")
        print("2. Run: ./download_models_manual.sh")
        print("3. Run this script again")
    
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main())
