import os
from typing import Literal

from dotenv import load_dotenv
from openai import OpenAI

type ModelName = Literal['deepseek_flash', 'gpt_luna']

load_dotenv()
DEEPSEEK = OpenAI(
    api_key=os.getenv('DEEPSEEK_API_KEY'),
    base_url='https://api.deepseek.com'
)

GPT = OpenAI(
    api_key=os.getenv('GPT_API_KEY'),
)

def call_deepseek_flash(system_prompt: str, request: str):
    return DEEPSEEK.chat.completions.create(
        model='deepseek-flash',
        messages=[
            {'role': 'system', 'content': system_prompt},
            {'role': 'user', 'content': f'{request}'}
        ],
        stream=False,
        reasoning_effort='max',
    )
    
def call_gpt_luna(system_prompt: str, request: str):
    return GPT.chat.completions.create(
        model='gpt-6-luna',
        messages=[
            {'role': 'system', 'content': system_prompt},
            {'role': 'user', 'content': f'{request}'}
        ],
        stream=False,
        reasoning_effort='xhigh',
    )

caller_map = {
    'deepseek_flash': call_deepseek_flash,
    'gpt_luna': call_gpt_luna,
}