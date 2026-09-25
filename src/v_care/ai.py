import os

from dotenv.main import load_dotenv
from openai import OpenAI

load_dotenv()

GPT = OpenAI(
    api_key=os.getenv('GPT_API_KEY'),
)


Deepseek = OpenAI(
    api_key=os.getenv('DEEPSEEK_API_KEY'),
    base_url='https://api.deepseek.com'
)


def call_deepseek_flash(system_prompt: str, request: str):
    return Deepseek.chat.completions.create(
        model='deepseek-flash',
        messages=[
            {'role': 'system', 'content': f'{system_prompt}'},
            {'role': 'user', 'content': f'{request}'}
        ],
        stream=False,
        reasoning_effort='max',
    )

def call_gpt_luna(system_prompt: str, request: str):
    return GPT.chat.completions.create(
        model='gpt-6-luna',
        messages=[
            {'role': 'system', 'content': f'{system_prompt}'},
            {'role': 'user', 'content': f'{request}'}
        ],
        stream=False,
        reasoning_effort='xhigh',
    )