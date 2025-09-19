#!/usr/bin/env python3
"""
Robust Model Downloader for OpenS2S Real-time Streaming
Handles large model downloads with progress bars and error recovery
"""

import os
import sys
import time
import argparse
from pathlib import Path
from typing import Optional, List, Tuple

try:
    from huggingface_hub import snapshot_download, hf_hub_download
    from huggingface_hub.utils import HfHubHTTPError
    HF_HUB_AVAILABLE = True
except ImportError:
    HF_HUB_AVAILABLE = False

try:
    from tqdm import tqdm
    TQDM_AVAILABLE = True
except ImportError:
    TQDM_AVAILABLE = False


class ModelDownloader:
    """Robust model downloader with multiple fallback strategies"""
    
    def __init__(self, models_dir: str = "/workspace/models"):
        self.models_dir = Path(models_dir)
        self.models_dir.mkdir(parents=True, exist_ok=True)
        
        # Model configurations
        self.models = {
            "OpenS2S": {
                "repo_id": "CASIA-LM/OpenS2S",
                "local_dir": self.models_dir / "OpenS2S",
                "required_files": ["config.json", "tokenizer.json"],
                "size_estimate": "~20GB"
            },
            "glm-4-voice-decoder": {
                "repo_id": "THUDM/glm-4-voice-decoder",
                "local_dir": self.models_dir / "glm-4-voice-decoder", 
                "required_files": ["config.json"],
                "size_estimate": "~5GB"
            }
        }
    
    def print_status(self, message: str, level: str = "INFO"):
        """Print colored status messages"""
        colors = {
            "INFO": "\033[0;32m",
            "WARN": "\033[1;33m", 
            "ERROR": "\033[0;31m",
            "STEP": "\033[0;34m"
        }
        reset = "\033[0m"
        print(f"{colors.get(level, '')}{message}{reset}")
    
    def check_prerequisites(self) -> bool:
        """Check if required packages are available"""
        if not HF_HUB_AVAILABLE:
            self.print_status("❌ huggingface-hub not available. Installing...", "WARN")
            try:
                import subprocess
                subprocess.check_call([sys.executable, "-m", "pip", "install", "huggingface-hub>=0.25.0"])
                self.print_status("✅ huggingface-hub installed successfully", "INFO")
                return True
            except Exception as e:
                self.print_status(f"❌ Failed to install huggingface-hub: {e}", "ERROR")
                return False
        return True
    
    def verify_model(self, model_name: str) -> bool:
        """Verify that a model was downloaded correctly"""
        model_config = self.models[model_name]
        local_dir = model_config["local_dir"]
        
        if not local_dir.exists():
            return False
        
        # Check required files
        for required_file in model_config["required_files"]:
            if not (local_dir / required_file).exists():
                self.print_status(f"❌ Missing required file: {required_file}", "ERROR")
                return False
        
        # Check for model weights (any of these formats)
        weight_files = [
            "pytorch_model.bin",
            "model.safetensors", 
            "pytorch_model-00001-of-*.bin",
            "model-00001-of-*.safetensors"
        ]
        
        has_weights = False
        for pattern in weight_files:
            if pattern.endswith("*"):
                # Handle patterns with wildcards
                import glob
                matches = glob.glob(str(local_dir / pattern))
                if matches:
                    has_weights = True
                    break
            else:
                if (local_dir / pattern).exists():
                    has_weights = True
                    break
        
        if not has_weights:
            # Check if there are any .bin or .safetensors files
            bin_files = list(local_dir.glob("*.bin"))
            safetensors_files = list(local_dir.glob("*.safetensors"))
            
            if bin_files or safetensors_files:
                has_weights = True
        
        if not has_weights:
            self.print_status(f"❌ No model weight files found in {local_dir}", "ERROR")
            return False
        
        self.print_status(f"✅ Model {model_name} verification passed", "INFO")
        return True
    
    def download_model_hf_hub(self, model_name: str) -> bool:
        """Download model using huggingface-hub"""
        model_config = self.models[model_name]
        
        try:
            self.print_status(f"📥 Downloading {model_name} ({model_config['size_estimate']})...", "STEP")
            self.print_status(f"Repository: {model_config['repo_id']}", "INFO")
            self.print_status(f"Destination: {model_config['local_dir']}", "INFO")
            
            # Use snapshot_download for complete model
            snapshot_download(
                repo_id=model_config["repo_id"],
                local_dir=str(model_config["local_dir"]),
                local_dir_use_symlinks=False,
                resume_download=True,
                ignore_patterns=["*.git*", "README.md", "*.md"]
            )
            
            return self.verify_model(model_name)
            
        except HfHubHTTPError as e:
            self.print_status(f"❌ HTTP error downloading {model_name}: {e}", "ERROR")
            return False
        except Exception as e:
            self.print_status(f"❌ Error downloading {model_name}: {e}", "ERROR")
            return False
    
    def download_model_git(self, model_name: str) -> bool:
        """Fallback: Download using git (if git-lfs is available)"""
        model_config = self.models[model_name]
        
        try:
            import subprocess
            
            # Check if git-lfs is available
            result = subprocess.run(["git", "lfs", "version"], 
                                  capture_output=True, text=True)
            if result.returncode != 0:
                self.print_status("❌ Git LFS not available", "ERROR")
                return False
            
            self.print_status(f"📥 Downloading {model_name} using git...", "STEP")
            
            # Clone the repository
            cmd = [
                "git", "clone", 
                f"https://huggingface.co/{model_config['repo_id']}", 
                str(model_config["local_dir"])
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                self.print_status(f"❌ Git clone failed: {result.stderr}", "ERROR")
                return False
            
            return self.verify_model(model_name)
            
        except Exception as e:
            self.print_status(f"❌ Git download failed: {e}", "ERROR")
            return False
    
    def download_model(self, model_name: str) -> bool:
        """Download a model with multiple fallback strategies"""
        if model_name not in self.models:
            self.print_status(f"❌ Unknown model: {model_name}", "ERROR")
            return False
        
        # Check if already downloaded and valid
        if self.verify_model(model_name):
            self.print_status(f"✅ Model {model_name} already downloaded and verified", "INFO")
            return True
        
        # Strategy 1: huggingface-hub (primary)
        if HF_HUB_AVAILABLE:
            self.print_status(f"🔄 Attempting download using huggingface-hub...", "STEP")
            if self.download_model_hf_hub(model_name):
                return True
        
        # Strategy 2: git with LFS (fallback)
        self.print_status(f"🔄 Attempting download using git...", "STEP")
        if self.download_model_git(model_name):
            return True
        
        self.print_status(f"❌ All download strategies failed for {model_name}", "ERROR")
        return False
    
    def download_all_models(self) -> bool:
        """Download all required models"""
        self.print_status("🚀 Starting model downloads for OpenS2S Real-time Streaming", "STEP")
        
        if not self.check_prerequisites():
            return False
        
        success = True
        for model_name in self.models.keys():
            if not self.download_model(model_name):
                success = False
        
        if success:
            self.print_status("✅ All models downloaded successfully!", "INFO")
            self.print_summary()
        else:
            self.print_status("❌ Some models failed to download", "ERROR")
        
        return success
    
    def print_summary(self):
        """Print download summary"""
        self.print_status("📊 Download Summary:", "STEP")
        
        for model_name, config in self.models.items():
            local_dir = config["local_dir"]
            if local_dir.exists():
                try:
                    import subprocess
                    result = subprocess.run(["du", "-sh", str(local_dir)], 
                                          capture_output=True, text=True)
                    if result.returncode == 0:
                        size = result.stdout.split()[0]
                        self.print_status(f"  {model_name}: {size}", "INFO")
                    else:
                        self.print_status(f"  {model_name}: Downloaded", "INFO")
                except:
                    self.print_status(f"  {model_name}: Downloaded", "INFO")


def main():
    parser = argparse.ArgumentParser(description="Download OpenS2S models")
    parser.add_argument("--models-dir", default="/workspace/models",
                       help="Directory to download models to")
    parser.add_argument("--model", choices=["OpenS2S", "glm-4-voice-decoder", "all"],
                       default="all", help="Which model to download")
    
    args = parser.parse_args()
    
    downloader = ModelDownloader(args.models_dir)
    
    if args.model == "all":
        success = downloader.download_all_models()
    else:
        success = downloader.download_model(args.model)
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
