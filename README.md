# cordant-gadgetry

Cordant’s public toolbox of scripts, snippets, and infrastructure magic for the community.  
Everything here is released under the [MIT License](LICENSE) — free to use, adapt, and share.  
⚠️ **Disclaimer**: Scripts are provided _as-is_ and used at your own risk. Always review and test before production use.

---

## 📂 Repository Structure

```bash
.
├── docs/                # Documentation served via MkDocs Material
│   └── Bash/
│   └── PowerShell/
│   └── Python/
│   └── Terraform/
├── scripts/             # Actual source scripts
│   ├── bash/
│   ├── powershell/
│   ├── python/
│   └── terraform/
├── pyproject.toml       # Poetry project definition
└── mkdocs.yml           # MkDocs site configuration
```

---

## 🚀 Getting Started

### Local setup

This project uses [Poetry](https://python-poetry.org/) to manage dependencies and build the docs site.

```bash
# Install pipx
brew install pipx # MacOS
scoop install pipx # Windows
pipx ensurepath

# Install Poetry if you don't have it
pipx install poetry

# Install dependencies
poetry install
```

### Local preview (optional)

You don’t need to build the site locally - the documentation is built and published automatically by GitHub Actions on every push/merge to `main`.

For development, you can preview the site locally:

```bash
poetry run mkdocs serve
```

This launches a live-reloading server at [http://127.0.0.1:8000](http://127.0.0.1:8000) so you can test changes before committing.

To do a one-off static build (optional):

```bash
poetry run mkdocs build --strict
```

---

## 🤝 How to Contribute

1. **Add your script** under [`scripts/`](./scripts/) in the right language folder.
   Example: `scripts/powershell/Fslogix-ResetProfile.ps1`

2. **Document it** with a new `.md` page in [`docs/`](./docs/), under the same language folder.
   The file should have the **same base name** as the script, but with `.md`.
   Example: `docs/powershell/Fslogix-ResetProfile.md`

3. **Use the template below**:

   ````markdown
   # Script name

   Brief description of what the script does.

   ```bash
   # Pre-requisites required to run the script (if any)
   ```

   ```language (bash|powershell|python|hcl)
   --8<-- "scripts/[language]/[script.ext]"
   ```
   ````

4. Submit a pull request 🚀

---

## 🔎 Search & Navigation

- Use the sidebar in the docs to browse scripts by language.
- Use the search bar (powered by Lunr.js) to find filenames, keywords, or topics.

---

## 📜 License

This repository is licensed under the [MIT License](LICENSE).
