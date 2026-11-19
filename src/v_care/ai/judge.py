from pydantic import TypeAdapter

from v_care.ai.models import ModelName, caller_map
from v_care.models.judgement import Judgement


class Judge:
    def __init__(self):
        self.system_prompt: str = '''
        <role>
        You are a senior security engineer who reviews remediation scripts in Bash.
        </role>
        
        <task>
        A vulnerability was detected on a service running inside a Docker container. 
        Review Bash scripts that claim they remediate the vulnerability when executed inside that container.
        
        Definitions:
        - FIXED: after the container is restarted, re-running the same check against the same port no longer reports the finding. The flaw may remain reachable by other paths (e.g. from inside the container).
        - CONTAINER STILL WORKS: after the container is restarted with its original entrypoint/command, it starts, stays running, and its other services keep working. The vulnerable feature itself going away is acceptable.
        </task>
        
        <strategies>
        Strategies the script can take to fix the vulnerability.
        1. config_change: minimal edit to the vulnerable software's own config (set a password, disable a feature/verb, change a cipher list, set a cookie flag).
        2. patch_update: a fixed version in the same major version, installable from distro repos (including archives) or upstream (vendor tarball/jar, vendor apt repo, build from source).
        3. major_update: the fix requires a newer major version of the software or a newer OS release, and the container can take that upgrade.
        4. disable: make the vulnerable surface unreachable from the network (bind it to localhost, turn off the vulnerable endpoint or listener). Not allowed if it would stop the container's main process from starting.
        5. uninstall: remove the package or files. Not allowed if the container's main process depends on them.
        </strategies>
        
        <input>
        You receive a JSON object with:
        - `environment_details`: details about the container in which the vulnerability was found and where the script will be executed;
        - `vulnerability_details`: details about the vulnerability;
        - `scripts`: a JSON object containing {script_author: script}
        </input>
        
        <response_format>
        Return only a JSON object with the following structure. Use double-quoted strings and JSON booleans.
        {
            <script_author_1>:
                {
                    "fixes_vulnerability": <does script_1 fix the vulnerability? true or false>,
                    "strategy": <strategy adopted by script_1 to fix the vulnerability (config_change, patch_update, etc.)>
                },
            <script_author_2>:
                {
                    "fixes_vulnerability": <does script_2 fix the vulnerability? true or false>,
                    "strategy": <strategy adopted by script_2 to fix the vulnerability (config_change, patch_update, etc.)>
                }
            ...
        }
        </response_format>
        '''

    def judge(
        self, 
        model: ModelName,
        patches: dict[ModelName, str],
        environment_details: str, 
        vulnerability_details: str
    ) -> dict[ModelName, Judgement]:
        request: str = f'''
        vulnerability_details: {vulnerability_details}
        environment_details: {environment_details}
        scripts: {patches}
        '''
        
        content = caller_map[model](
            system_prompt=self.system_prompt, request=request
        ).choices[0].message.content
        
        if content is None:
            raise ValueError("The judge returned no message content")
        return TypeAdapter(dict[ModelName, Judgement]).validate_json(content, strict=True)
