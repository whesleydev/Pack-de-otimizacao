
import re

with open('app/src/main/assets/panel/index.html', 'r') as f:
    content = f.read()

# Pattern to match <article ...> ... </article> containing "chip root"
# This is a bit simplistic, but it should work for this HTML structure.
# We need a non-greedy match for article, and then check for root inside.
pattern = re.compile(r'<article[^>]*>.*?<span class="chip root">root</span>.*?</article>', re.DOTALL)

new_content = pattern.sub('', content)

with open('app/src/main/assets/panel/index.html', 'w') as f:
    f.write(new_content)
