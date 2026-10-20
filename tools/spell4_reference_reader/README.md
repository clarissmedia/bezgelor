# Lecteurs de référence isolés

Ces outils utilisent le SDK .NET 8 déjà installé, sans paquet NuGet ajouté. Ils
compilent des liens vers les fichiers C# **en lecture seule**, avec leurs sorties
uniquement dans ce répertoire (`bin/`, `obj/`) et dans le workspace. Ils ne
construisent pas le projet NexusForever et ne lancent aucun serveur.

Depuis la racine du workspace, PowerShell :

```powershell
dotnet build tools/spell4_reference_reader/ReferenceReader.csproj -p:NexusForeverSource=E:/WILDSTAR/SERVEUR/REWORK/Source
dotnet tools/spell4_reference_reader/bin/Debug/net8.0/ReferenceReader.dll E:/WILDSTAR/SERVEUR/WORLD/tbl/Spell4.tbl logs/spell4-engine/nf-Spell4.json
```

Répéter cette dernière commande pour les vingt noms de tables listés dans
`tools/audit_spell4_phases.exs`, puis `Class` et `ItemDisplay` pour l'audit
historique. Le lecteur de valeurs est le `GameTable<T>.ReadEntries` original,
sans modification. L'adaptateur émet un modèle scalaire dynamique à partir du
schéma binaire et convertit les résultats `float` en `double` avant sérialisation
pour conserver leur valeur exacte. L'export se limite aux types reconnus.

Dans le conteneur de test, avec les copies TBL sous le workspace :

```sh
MIX_ENV=test MIX_BUILD_PATH=/tmp/bezgelor-spell4-build mix run --no-start tools/audit_spell4_phases.exs logs/spell4-engine/tbl logs/spell4-engine logs/spell4-engine/reproduced-phases.json
```

L'audit compare tous les champs de tous les enregistrements aux exports C# et
vérifie aussi les lignes et empreintes du catalogue sélectif existant. Il échoue
à la première divergence. Les tables originales ne sont jamais des sorties.

Pour reproduire les observations géométriques, utiliser les sources du commit
`f9bb26efddbf304003fc8ebf484ac75bc6be84da`, dont les empreintes sont dans le
fichier de vecteurs. `NexusForeverSource` doit désigner cette copie de sources :

```powershell
dotnet build tools/spell4_reference_reader/GeometryReader.csproj -p:NexusForeverSource=E:/WILDSTAR/BEZGELOR/source/logs/spell4-engine/upstream/Source
dotnet tools/spell4_reference_reader/bin/Debug/net8.0/GeometryReader.dll docs/reports/2026-10-20-quick-draw-geometry-vectors.json logs/spell4-engine/reproduced-geometry.json logs/spell4-engine/upstream/Source
```

Le fichier de vecteurs sert aussi d'entrée : les valeurs `expected` sont
recalculées par `Telegraph.InsideTelegraph` C# original. Les adaptateurs locaux
ne servent qu'à fournir un lanceur de rayon nul et à éviter la dépendance à
NLog. La recherche de carte lève une exception si elle est appelée. Aucun
algorithme géométrique n'est réimplémenté dans l'adaptateur C#.

Pour le suivi `source-7` (lecture et comparaison, sans régénération des JSON) :

```powershell
python tools/audit_tbl_layout.py E:/WILDSTAR/SERVEUR/WORLD/tbl apps/bezgelor_data/priv/data logs/spell4-engine logs/spell4-engine/reproduced-layout.json
```

Les extractions et comparaisons de fichiers C#/Python s'effectuent sur l'hôte.
Les tests automatisés Elixir, y compris la consommation des observations C#,
s'exécutent uniquement dans `bezgelor-gameplay-test`.
