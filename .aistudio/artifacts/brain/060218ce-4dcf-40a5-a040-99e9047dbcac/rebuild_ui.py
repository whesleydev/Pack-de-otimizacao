
import json

with open('/app/src/main/assets/panel/actions.json', 'r') as f:
    actions = json.load(f)

# Filter out root-dependent actions
safe_actions = [a for a in actions if a.get('risk') != 'root']

# Reorganize and clean up (simplified grouping)
# New Categories: Principal, Otimização, Rede, Sistema
for a in safe_actions:
    if a['group'] in ['Geral', 'Painel']:
        a['group'] = 'Principal'
    elif a['group'] in ['Desempenho', 'Apps e jogos', 'Display & Touch']:
        a['group'] = 'Otimização'
    elif a['group'] in ['DNS e rede']:
        a['group'] = 'Rede'
    else:
        a['group'] = 'Sistema'

# Save the filtered actions back if needed (or just use them to build the new index.html)
with open('/app/src/main/assets/panel/actions_safe.json', 'w') as f:
    json.dump(safe_actions, f, indent=4)

print("Root actions removed and actions grouped.")
