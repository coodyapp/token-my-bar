# Wiki staging

GitHub Wikis are unavailable on private free-plan repositories. These pages are
staged here; once the repo is public (or on a paid plan), publish them with:

```bash
gh api -X PATCH repos/coodyapp/token-my-bar -F has_wiki=true
git clone https://github.com/coodyapp/token-my-bar.wiki.git /tmp/tmb-wiki
cp wiki/*.md /tmp/tmb-wiki/ && rm /tmp/tmb-wiki/README.md
cd /tmp/tmb-wiki && git add -A && git commit -m "Publish wiki" && git push
```
