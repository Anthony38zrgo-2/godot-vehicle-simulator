import json

paths = [
    'game/assets/rally/lancia_fulvia/manifest.json',
    'tmp/porsche_mod/cache/validation_project/assets/rally/lancia_fulvia/manifest.json'
]

for p in paths:
    with open(p, 'rb') as f:
        content = f.read().decode('utf-8')
    content = content.replace(
        '"sha256": "a7ac07d7f7e811f2bb89f39fe0c9ab3109d996e578f39f13754c2e4f8a306bed",\r\n    "size_bytes": 1387456',
        '"sha256": "cf18a7b5764072c35cdae412abe7623e70f0611407152b1e811f70d79e78d055",\r\n    "size_bytes": 1414508'
    )
    content = content.replace(
        '"936277a1c4ff4d814cd686401ebb9484db7ff666757bffb5663a973a76e5eac6"',
        '"a55acec300375695ff6699007cf30759961b085f11bd1a306d39b020555f4594"'
    )
    with open(p, 'wb') as f:
        f.write(content.encode('utf-8'))
    print(f'Updated {p}')
