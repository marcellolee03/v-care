import os
from typing import Literal

from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()
class Generator:
    def __init__(self):
        self.caller_map = {
            'deepseek_flash': self._call_deepseek_flash,
            'gpt_luna': self._call_gpt_luna,
        }
        
        self.system_prompt = '''
        <role>
        You are a senior security engineer who writes remediation scripts in Bash.
        </role>
        
        <task>
        The finding was detected on a service running inside a Docker container. Write a Bash script that remediates it when executed inside that container.
        
        Definitions:
        - FIXED: after the container is restarted, re-running the same check against the same port no longer reports the finding. The flaw may remain reachable by other paths (e.g. from inside the container).
        - CONTAINER STILL WORKS: after the container is restarted with its original entrypoint/command, it starts, stays running, and its other services keep working. The vulnerable feature itself going away is acceptable.
        </task>
        
        <execution_context>
        - The script is run with `docker exec`, non-interactively, as the user in `environment_info`.
        - After the script finishes, the container is restarted with `docker restart`. Changes written to the container's filesystem persist across that restart; running processes and in-memory state do not.
        - There is no systemd and usually no init system. The main service is often PID 1: never kill or stop PID 1, and do not rely on `systemctl` or `service`.
        - Containers usually lack the NET_ADMIN capability, so iptables/nftables rules will not work.
        - The reported `Port` is the port published on the Docker host; the port inside the container may differ. Determine it from the service's configuration.
        - Only rely on tools listed in `environment_info`, plus coreutils and the shell.
        - No prompts: use `DEBIAN_FRONTEND=noninteractive`, `-y` and similar flags. Package lists are often empty in images, so update them before installing.
        </execution_context>
        
        <strategy>
        Choose the FIRST tier you are confident will work in this container:
        1. config_change: minimal edit to the vulnerable software's own config (set a password, disable a feature/verb, change a cipher list, set a cookie flag).
        2. patch_update: a fixed version in the same major version, installable from distro repos (including archives) or upstream (vendor tarball/jar, vendor apt repo, build from source).
        3. major_update: the fix requires a newer major version of the software or a newer OS release, and the container can take that upgrade.
        4. disable: make the vulnerable surface unreachable from the network (bind it to localhost, turn off the vulnerable endpoint or listener). Not allowed if it would stop the container's main process from starting.
        5. uninstall: remove the package or files. Not allowed if the container's main process depends on them.
        </strategy>
        
        <input>
        You receive a JSON object with:
        - `vulnerability_details`: details about the vulnerability;
        - `environment_details`: details about the container in which the script will be executed;
        </input>
        
        <response_format>
        Output only the script as raw text: no Markdown fences and no prose outside the script.
        </response_format>
        '''
        
    def _call_deepseek_flash(self, request: str):
        model = OpenAI(
            api_key=os.getenv('DEEPSEEK_API_KEY'),
            base_url='https://api.deepseek.com'
        )
        
        return model.chat.completions.create(
            model='deepseek-flash',
            messages=[
                {'role': 'system', 'content': self.system_prompt},
                {'role': 'user', 'content': f'{request}'}
            ],
            stream=False,
            reasoning_effort='max',
        )
    
    def _call_gpt_luna(self, request: str):
        model = OpenAI(
            api_key=os.getenv('GPT_API_KEY'),
        )

        return model.chat.completions.create(
            model='gpt-6-luna',
            messages=[
                {'role': 'system', 'content': self.system_prompt},
                {'role': 'user', 'content': f'{request}'}
            ],
            stream=False,
            reasoning_effort='xhigh',
        )

    def generate(
        self, 
        model: Literal['deepseek_flash', 'gpt_luna'], 
        environment_details: str, 
        vulnerability_details: str
    ):
        request: str = f'''
        vulnerability_details: {vulnerability_details}
        environment_details: {environment_details}
        '''
        return self.caller_map[model](request).choices[0].message.content