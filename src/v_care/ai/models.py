import os
from typing import Literal

from dotenv import load_dotenv
from openai import OpenAI

type ModelName = Literal['deepseek_flash', 'gpt_luna', 'gpt_sol', 'gemini_hydrogen']
type GeneratorModelName = Literal['deepseek_flash', 'gemini_hydrogen']

load_dotenv()
DEEPSEEK = OpenAI(
    api_key=os.getenv('DEEPSEEK_API_KEY'),
    base_url='https://api.deepseek.com',
)

GPT = OpenAI(
    api_key=os.getenv('GPT_API_KEY'),
)

GEMINI = OpenAI(
    api_key=os.getenv('GEMINI_API_KEY'),
    base_url='https://generativelanguage.googleapis.com/v1beta/openai/',
)


def call_deepseek_flash(system_prompt: str, request: str):
    return DEEPSEEK.chat.completions.create(
        model='deepseek-flash',
        messages=[
            {'role': 'system', 'content': system_prompt},
            {'role': 'user', 'content': f'{request}'},
        ],
        stream=False,
        reasoning_effort='max',
    )


def call_gpt_luna(system_prompt: str, request: str):
    return GPT.chat.completions.create(
        model='gpt-6-luna',
        messages=[
            {'role': 'system', 'content': system_prompt},
            {'role': 'user', 'content': f'{request}'},
        ],
        stream=False,
        reasoning_effort='xhigh',
    )


def call_gpt_sol(system_prompt: str, request: str):
    return GPT.chat.completions.create(
        model='gpt-6.2-sol',
        messages=[
            {'role': 'system', 'content': system_prompt},
            {'role': 'user', 'content': f'{request}'},
        ],
        stream=False,
        reasoning_effort='xhigh',
    )


def call_gemini_hydrogen(system_prompt: str, request: str):
    return GEMINI.chat.completions.create(
        model='gemini-4-hydrogen',
        messages=[
            {'role': 'system', 'content': system_prompt},
            {'role': 'user', 'content': f'{request}'},
        ],
        stream=False,
        reasoning_effort='xhigh',
    )


caller_map = {
    'deepseek_flash': call_deepseek_flash,
    'gpt_luna': call_gpt_luna,
    'gpt_sol': call_gpt_sol,
    'gemini_hydrogen': call_gemini_hydrogen,
}
