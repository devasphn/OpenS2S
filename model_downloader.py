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
        
        # Model configurations with comprehensive required files
        self.models = {
            "OpenS2S": {
                "repo_id": "CASIA-LM/OpenS2S",
                "local_dir": self.models_dir / "OpenS2S",
                "required_files": [
                    "config.json",
                    "tokenizer.json",
                    "tokenizer_config.json"
                ],
                "required_patterns": [
                    "*.safetensors",  # Model weights in safetensors format
                    "*.bin"           # Alternative: model weights in bin format
                ],
                "size_estimate": "~20GB",
                "description": "OpenS2S main model with tokenizer and weights"
            },
            "glm-4-voice-decoder": {
                "repo_id": "THUDM/glm-4-voice-decoder",
                "local_dir": self.models_dir / "glm-4-voice-decoder",
                "required_files": [
                    "config.yaml",
                    "flow.pt",
                    "hift.pt"
                ],
                "required_patterns": [],
                "size_estimate": "~5GB",
                "description": "GLM-4 Voice Decoder with flow and hift models (uses YAML config)"
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
    
    def verify_model(self, model_name: str, verbose: bool = True) -> Tuple[bool, List[str]]:
        """
        Comprehensively verify that a model was downloaded correctly
        Returns: (is_valid, missing_files)
        """
        model_config = self.models[model_name]
        local_dir = model_config["local_dir"]
        missing_files = []

        if not local_dir.exists():
            if verbose:
                self.print_status(f"❌ Model directory does not exist: {local_dir}", "ERROR")
            return False, ["directory_missing"]

        # Check required files
        for required_file in model_config["required_files"]:
            file_path = local_dir / required_file
            if not file_path.exists():
                missing_files.append(required_file)
                if verbose:
                    self.print_status(f"❌ Missing required file: {required_file}", "ERROR")

        # Check required patterns (like *.safetensors)
        for pattern in model_config.get("required_patterns", []):
            import glob
            matches = list(local_dir.glob(pattern))
            if not matches:
                missing_files.append(f"pattern:{pattern}")
                if verbose:
                    self.print_status(f"❌ No files matching pattern: {pattern}", "ERROR")

        # Special handling for OpenS2S model weights
        if model_name == "OpenS2S":
            has_weights = False
            weight_patterns = ["*.safetensors", "*.bin"]

            for pattern in weight_patterns:
                matches = list(local_dir.glob(pattern))
                if matches:
                    has_weights = True
                    if verbose:
                        self.print_status(f"✅ Found {len(matches)} weight files matching {pattern}", "INFO")
                    break

            if not has_weights:
                missing_files.append("model_weights")
                if verbose:
                    self.print_status(f"❌ No model weight files found (.safetensors or .bin)", "ERROR")

        # Validate file sizes (basic check for corruption)
        for required_file in model_config["required_files"]:
            file_path = local_dir / required_file
            if file_path.exists():
                file_size = file_path.stat().st_size
                if file_size == 0:
                    missing_files.append(f"{required_file}:empty")
                    if verbose:
                        self.print_status(f"❌ File is empty: {required_file}", "ERROR")
                elif file_size < 100:  # Suspiciously small for config files
                    if verbose:
                        self.print_status(f"⚠️  File suspiciously small: {required_file} ({file_size} bytes)", "WARN")

        is_valid = len(missing_files) == 0

        if is_valid and verbose:
            self.print_status(f"✅ Model {model_name} verification passed", "INFO")
        elif not is_valid and verbose:
            self.print_status(f"❌ Model {model_name} verification failed: {len(missing_files)} issues", "ERROR")

        return is_valid, missing_files

    def cleanup_partial_download(self, model_name: str) -> bool:
        """Remove partial/corrupted model download"""
        model_config = self.models[model_name]
        local_dir = model_config["local_dir"]

        if not local_dir.exists():
            return True

        try:
            import shutil
            self.print_status(f"🧹 Cleaning up partial download: {local_dir}", "WARN")
            shutil.rmtree(local_dir)
            self.print_status(f"✅ Cleanup completed for {model_name}", "INFO")
            return True
        except Exception as e:
            self.print_status(f"❌ Failed to cleanup {model_name}: {e}", "ERROR")
            return False

    def get_model_status(self, model_name: str) -> str:
        """Get detailed status of model download"""
        is_valid, missing_files = self.verify_model(model_name, verbose=False)

        if is_valid:
            return "complete"
        elif not self.models[model_name]["local_dir"].exists():
            return "not_started"
        elif missing_files:
            return f"partial ({len(missing_files)} missing)"
        else:
            return "unknown"

    def download_model_hf_hub(self, model_name: str) -> bool:
        """Download model using huggingface-hub with validation"""
        model_config = self.models[model_name]

        try:
            self.print_status(f"📥 Downloading {model_name} ({model_config['size_estimate']})...", "STEP")
            self.print_status(f"Repository: {model_config['repo_id']}", "INFO")
            self.print_status(f"Destination: {model_config['local_dir']}", "INFO")
            self.print_status(f"Description: {model_config['description']}", "INFO")

            # Use snapshot_download for complete model
            snapshot_download(
                repo_id=model_config["repo_id"],
                local_dir=str(model_config["local_dir"]),
                local_dir_use_symlinks=False,
                resume_download=True,
                ignore_patterns=["*.git*", "README.md", "*.md", ".gitattributes"]
            )

            # Verify download completeness
            is_valid, missing_files = self.verify_model(model_name)

            if is_valid:
                self.print_status(f"✅ {model_name} downloaded and verified successfully", "INFO")
                return True
            else:
                self.print_status(f"❌ {model_name} download incomplete. Missing: {missing_files}", "ERROR")
                self.print_status(f"🔄 Attempting to re-download missing files...", "WARN")

                # Try to download missing files individually
                for missing_file in missing_files:
                    if not missing_file.startswith("pattern:") and not missing_file.endswith(":empty"):
                        try:
                            self.print_status(f"📥 Downloading missing file: {missing_file}", "INFO")
                            hf_hub_download(
                                repo_id=model_config["repo_id"],
                                filename=missing_file,
                                local_dir=str(model_config["local_dir"]),
                                local_dir_use_symlinks=False
                            )
                        except Exception as e:
                            self.print_status(f"❌ Failed to download {missing_file}: {e}", "ERROR")

                # Re-verify after individual downloads
                is_valid, remaining_missing = self.verify_model(model_name)
                if is_valid:
                    self.print_status(f"✅ {model_name} completed after individual file downloads", "INFO")
                    return True
                else:
                    self.print_status(f"❌ {model_name} still incomplete after retry: {remaining_missing}", "ERROR")
                    return False

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

            # If directory exists, remove it first (handle partial downloads)
            if model_config["local_dir"].exists():
                self.print_status(f"🧹 Removing existing directory for fresh clone", "WARN")
                if not self.cleanup_partial_download(model_name):
                    return False

            # Clone the repository
            cmd = [
                "git", "clone",
                f"https://huggingface.co/{model_config['repo_id']}",
                str(model_config["local_dir"])
            ]

            self.print_status(f"🔄 Running: {' '.join(cmd)}", "INFO")
            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode != 0:
                self.print_status(f"❌ Git clone failed: {result.stderr}", "ERROR")
                return False

            # Verify the download
            is_valid, missing_files = self.verify_model(model_name)

            if is_valid:
                self.print_status(f"✅ {model_name} downloaded via git successfully", "INFO")
                return True
            else:
                self.print_status(f"❌ Git download incomplete. Missing: {missing_files}", "ERROR")
                return False

        except Exception as e:
            self.print_status(f"❌ Git download failed: {e}", "ERROR")
            return False
    
    def download_model(self, model_name: str) -> bool:
        """Download a model with multiple fallback strategies and intelligent partial download handling"""
        if model_name not in self.models:
            self.print_status(f"❌ Unknown model: {model_name}", "ERROR")
            return False

        model_config = self.models[model_name]

        # Check current status
        status = self.get_model_status(model_name)
        self.print_status(f"📊 Current status of {model_name}: {status}", "INFO")

        if status == "complete":
            self.print_status(f"✅ Model {model_name} already downloaded and verified", "INFO")
            return True
        elif status.startswith("partial"):
            self.print_status(f"⚠️  Detected partial download of {model_name}", "WARN")
            is_valid, missing_files = self.verify_model(model_name, verbose=True)

            # Ask user preference for partial downloads (in automated mode, clean up)
            self.print_status(f"🧹 Cleaning up partial download to ensure complete download", "WARN")
            if not self.cleanup_partial_download(model_name):
                self.print_status(f"❌ Failed to cleanup partial download", "ERROR")
                return False

        # Strategy 1: huggingface-hub (primary)
        if HF_HUB_AVAILABLE:
            self.print_status(f"🔄 Strategy 1: Attempting download using huggingface-hub...", "STEP")
            if self.download_model_hf_hub(model_name):
                return True
            else:
                self.print_status(f"❌ Huggingface-hub download failed", "ERROR")

        # Strategy 2: git with LFS (fallback)
        self.print_status(f"🔄 Strategy 2: Attempting download using git...", "STEP")
        if self.download_model_git(model_name):
            return True
        else:
            self.print_status(f"❌ Git download failed", "ERROR")

        self.print_status(f"❌ All download strategies failed for {model_name}", "ERROR")
        self.print_status(f"💡 You can try manual download: ./download_models_manual.sh", "INFO")
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
        """Print comprehensive download summary"""
        self.print_status("📊 Download Summary:", "STEP")

        for model_name, config in self.models.items():
            local_dir = config["local_dir"]
            status = self.get_model_status(model_name)

            if status == "complete":
                try:
                    import subprocess
                    result = subprocess.run(["du", "-sh", str(local_dir)],
                                          capture_output=True, text=True)
                    if result.returncode == 0:
                        size = result.stdout.split()[0]
                        self.print_status(f"  ✅ {model_name}: {size} - COMPLETE", "INFO")
                    else:
                        self.print_status(f"  ✅ {model_name}: COMPLETE", "INFO")
                except:
                    self.print_status(f"  ✅ {model_name}: COMPLETE", "INFO")
            elif status.startswith("partial"):
                self.print_status(f"  ⚠️  {model_name}: {status.upper()}", "WARN")
                is_valid, missing_files = self.verify_model(model_name, verbose=False)
                self.print_status(f"      Missing: {', '.join(missing_files[:3])}{'...' if len(missing_files) > 3 else ''}", "WARN")
            elif status == "not_started":
                self.print_status(f"  ❌ {model_name}: NOT DOWNLOADED", "ERROR")
            else:
                self.print_status(f"  ❓ {model_name}: {status.upper()}", "WARN")


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
