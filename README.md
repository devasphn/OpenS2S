# OpenS2S: Advancing Fully Open-Source End-to-End Empathetic Large Speech Language Model

We present OpenS2S, a fully open-source, transparent and end-to-end large speech language model designed to enable empathetic speech interactions.


<a href='https://huggingface.co/CASIA-LM/OpenS2S'><img src='https://img.shields.io/badge/%F0%9F%A4%97%20Hugging%20Face-Checkpoint-blue'></a> <a href='https://huggingface.co/datasets/CASIA-LM/OpenS2S_Datasets'><img src='https://img.shields.io/badge/%F0%9F%A4%97%20Hugging%20Face-Dataset-blue'></a> <a href=''><img src='https://img.shields.io/badge/Paper-Arxiv-red'></a> <a href='https://casia-lm.github.io/OpenS2S'><img src='https://img.shields.io/badge/Project-Page-Green'></a> 


## Model Architecture

![architecture](figures/Architecture.png)

As shown in the figure, OpenS2S consists of the following main components:

* Audio Encoder: The Audio Encoder is responsible for transforming this raw audio signal into a more manageable and meaningful representation.

* Instruction-Following LLM: The audio embeddings and text embeddings are concatenated to form interleaved input sequences for the large language model. We select Qwen3-8B-Instruct as the LLM, leveraging its robust text processing capabilities.

* Streaming Speech Decoder: The speech response is first converted into discrete tokens
using a supervised semantic speech tokenizer. Then, an autoregressive text-to-speech language model is used to generate speech tokens conditioned on the hidden states of the LLM, enabling real-time generation.

## Example

More examples can be found in the [project page](https://casia-lm.github.io/OpenS2S).


## Usage

### Setup

```bash
pip install requirements.txt
```


### Prepare the pretrained OpenS2S checkpoint

Download the pretrained OpenS2S model from [Huggingface](https://huggingface.co/CASIA-LM/OpenS2S).


### Inference

1. Start the controller
```bash
python controller.py
```
2. Start the model server
```bash
python model_worker.py
```

3. Launching web service locally
```bash
python web_demo.py --port 8888
```

## Training

### Data Preparation

This code requires input data to be in JSON Lines (jsonl) format. Each line of the file must be a valid JSON object containing exactly one key: messages.

Here is an example of a valid line in the jsonl file:
```python
{
    "messages": [
        {
            "role": "user", 
            "content": [
                {"text": "continue the following sentence", "audio": "", "speech_units": "", "spk_emb": ""},
                {"text": "", "audio": "/path/to/audio", "speech_units": "", "spk_emb": ""}
            ]
        },
        {
            "role": "assistant", 
            "content": [
                {"text": "hello", "audio": "", "speech_units": "<|audio_0|><|audio_1|>", "spk_emb": ""},
            ]
        }
    ]
}
```

If you want to construct continuation writing based on ASR data, please refer to [text_generation.py](./text_generation.py). If you want to convert audio waveform into speech units, please refer to [GLM-4-Voice](https://github.com/THUDM/GLM-4-Voice/blob/main/speech_tokenizer/utils.py#L40).


###  Train from scratch
1. Obtain the Audio Encoder, LLM bachbone, and Auto-regressive TTS LM.

2. Offline process training data
``` bash
export llm_path=/path/to/llm_backbone
export tts_path=/path/to/ar_tts
export audio_path=path/to/audio_encoder
python src/instruction_dataset.py offline \
    --dataroot /path/to/raw_data_dir \
    --manifest_files "*.jsonl" \
    --llm_path ${llm_path} \
    --tts_path ${tts_path} \
    --save_dir /path/to/processed_data_dir \
    --num_proc 64
```

4. train the model (connect different modules)
```bash
export data_dir=/path/to/processed_data_dir
export SAVE_ROOT=/path/to/checkpoints

bash scripts/train_from_scratch.sh
```


### Fine-tuning
1. Obtain pretrained checkpoints

2. Offline process
``` bash
export omnispeech_path=/path/to/omnispeech

python src/instruction_dataset.py offline \
    --dataroot /path/to/raw_data_dir \
    --manifest_files "*.jsonl" \
    --llm_path ${omnispeech_path} \
    --tts_path ${omnispeech_path}/tts/ \
    --save_dir /path/to/processed_data_dir \
    --num_proc 64
```

3. fine-tune the pretrained model
```bash
bash scripts/train_continue.sh
```



## License
* The license of our project is [Apache License 2.0]()

## Citation
If you find our project useful, hope you can star our repo and cite our paper as follows:
```
TODO
```