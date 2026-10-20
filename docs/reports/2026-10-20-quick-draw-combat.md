Quick Draw 43468 — audit et sécurisation du combat, 20 octobre 2026

Quick Draw **ne produit pas encore de dégâts réels**. Les sources locales permettent de confirmer les types d'effets et les références proxy, mais pas de calculer un montant fiable ni de choisir les phases et les cibles. L'exécution de 43468 et de ses deux proxies de dégâts est désormais explicitement refusée. Aucun dégât artificiel n'a été ajouté.

Les modifications non commitées présentes au début de la session sont conservées dans le commit distinct `25c9ad6` (diagnostic Spell4, cycle d'incantation, tests et fichiers d'audit). Les modifications de cette session viennent ensuite. Branche : `repair/spell4-effects-audit`.

Les données brutes sélectionnées et les empreintes SHA-256 des tables lues sont dans [quick-draw-evidence.json](2026-10-20-quick-draw-evidence.json). Les journaux de validation accompagnent ce rapport dans `2026-10-20-quick-draw-validation.txt`.

**Preuves disponibles et limites d'interprétation**

Sources lues sans modification :

- `E:/WILDSTAR/BEZGELOR/spell4_reference`, `spell4_effects_selected.json`, `spell4_effect_chain_audit.json`, `spell4_interpretation_reference.json`, `spell4_effect_chain_report.md`.
- `E:/WILDSTAR/SERVEUR/REWORK/Source/NexusForever.GameTable/Model/Spell4EffectsEntry.cs`, `SpellPhaseEntry.cs`, `SpellEffectTypeEntry.cs` et modèles de ciblage.
- `NexusForever.Game.Static/Spell/SpellEffectType.cs`, `SpellEffectTargetFlags.cs`, `DamageType.cs`, `DamageShape.cs`.
- `NexusForever.Game/Spell/SpellEffectHandler.cs` et `Spell.cs`.
- Tables originales dans `NexusForever.WorldServer/bin/Release/net7.0/tbl`, ouvertes en lecture binaire par `tools/tbl_extractor/tbl_extractor.py` ; aucune extraction écrite dans NexusForever.
- Entrées JSON Spell4 déjà présentes dans `apps/bezgelor_data/priv/data`.

| Élément | Constat vérifié |
| --- | --- |
| Type 8 | `Damage` ; `DamageType=1` correspond à Physical. |
| Type 26 | `Proxy` ; le gestionnaire NexusForever appelle `target.CastSpell(DataBits00, ...)` avec les informations du parent et de la racine. |
| Type 17 | `Fluff`, cohérent avec le libellé de 43500 « Visual Fluff ». Ce n'est pas un effet de dégâts. |
| Type 80 | `SpellForceRemove`, pas un proxy de dégâts supplémentaire. |
| TargetFlags 1 / 4 | Caster / Telegraph dans l'énumération NexusForever. Ne pas convertir 4 en « cible sélectionnée ». |
| Sort racine 43468 | `castTime=0`, `spellDuration=1000`, `targetMaxRange=0`, neuf effets. La durée et les phases ne sont pas équivalentes à une incantation simple de 1000 ms. |
| Proxies de dégâts | 43498 (Impact Right), effet 99526 ; 43499 (Impact Left), effet 99528. Trois références de chaque proxy, avec masques 2, 4 et 8. |
| Paramètres de dégâts | Pour chacun : `DataBits00=1065353216`, les autres DataBits nuls ; `ParameterType00=12`, `ParameterValue00=0.1029`, `ParameterType01=10`, `ParameterValue01=5.5`. Les valeurs existent, leur formule d'évaluation n'est pas fournie. |
| Phases | Cinq lignes SpellPhase 5882–5886 : `(orderIndex, phaseDelay, phaseFlags)` = `(0,0,0)`, `(1,366,512)`, `(2,200,0)`, `(3,200,4)`, `(4,234,0)`. Ces flags ne doivent pas être assimilés sans preuve aux masques des effets. |
| Télégraphes | Racine vers 3693 ; les deux impacts vers 3694. Shape 8 = LongCone, paramètres bruts `3,27,15,0,20,0`, décalage Z -2, flags de dégâts distincts. Aucune portée ni sélection de cibles n'en a été déduite pour l'exécution. |

Le blocage précis se trouve dans `NexusForever.Game/Spell/SpellEffectHandler.cs`, méthode `HandleEffectDamage` : elle contient `TODO: calculate damage` et passe la constante `1337` à `AddDamage`. Ce nombre est un substitut de développement, pas une formule validée. La recherche des usages de `ParameterType00`/`ParameterValue00` dans les sources locales ne fournit que la déclaration de table, aucun évaluateur. `Spell.cs.ExecuteEffects` parcourt les effets et filtre leurs TargetFlags, sans interpréter leurs PhaseFlags. Copier ce code appliquerait donc potentiellement plusieurs impacts à tort.

**Comportements implémentés**

- `Spell4CombatSupport` bloque explicitement 43468, 43498 et 43499. `SpellManager.cast_spell` renvoie `{:error, :unverified_spell4_combat}` avant timer, calcul d'effets ou cooldown ; `spell_ready?` renvoie faux pour ces IDs. Ce module n'accorde aucun support supplémentaire aux autres sorts.
- `SpellHandler` journalise le blocage et renvoie l'échec générique déjà disponible dans le protocole, sans inventer de code réseau. L'entrée de résolution des incantations refuse aussi ces IDs. Aucun SpellStart/Go de succès vide ni paquet de dégâts n'est produit pour une requête Quick Draw bloquée.
- Pour les sorts existants définis avec `target_type: :enemy` et des dégâts directs, la cible doit être une créature présente et vivante dans l'instance du lanceur. Une instance absente, un joueur, un GUID nul ou inconnu sont refusés. La distance utilise la position serveur de la créature et la portée déjà définie du sort. La cible et la distance sont revérifiées à la résolution ; une cible hors de portée renvoie `out_of_range`.
- Le chemin de dégâts existant est réutilisé : `SpellEffect` → `SpellHandler` → `World.Instance.damage_creature` → `CreatureState.apply_damage` → `CreatureDeath` → `CombatBroadcaster.send_kill_rewards` → `Characters.add_experience`. Les formules de démonstration et les récompenses existantes ne sont pas présentées comme des formules WildStar vérifiées.
- Les jetons d'incantation préexistants protègent contre les timers annulés ou répétés. Une créature déjà morte ne délivre pas une seconde récompense. Les tests vérifient une relecture de l'XP persistée, pas seulement un paquet réseau.

**Validation**

Exécution uniquement dans `bezgelor-gameplay-test`, répertoire `/workspace`, `MIX_ENV=test`, avec PostgreSQL `bezgelor-gameplay-test-db:5432`, `POSTGRES_DB=bezgelor_test`. Les identifiants sont récupérés depuis la configuration du seul conteneur PostgreSQL de test et ne sont pas inscrits dans les artefacts. Les créations de personnages des tests sont isolées par le sandbox SQL et annulées à la fin de chaque test.

- Compilation de toute l'umbrella : `mix compile --force --warnings-as-errors`, réussie, code de sortie 0.
- Campagne ciblée élargie : `mix test` sur les douze fichiers ci-dessous, avec `--include integration --warnings-as-errors --seed 20261020` : **111 tests, 0 échec** (core 40, protocole 23, monde 48), dont 13 nouvelles régressions. Une première campagne élargie avec la graine 0 avait aussi réussi ; les nombres ne sont pas additionnés.
- Formatage vérifié explicitement sur les dix fichiers Elixir modifiés : code de sortie 0.
- `mix precommit` exécuté ; son contrôle global de formatage échoue sur **43 fichiers préexistants** hors de ce correctif, code de sortie 1. Son étape de tests n'est donc pas atteinte. Le suivi global existe dans `source-3` ; la suite complète du dépôt n'est pas déclarée verte. La liste des fichiers figure dans le journal de validation.

Fichiers de la campagne :

```text
apps/bezgelor_core/test/spell_test.exs
apps/bezgelor_core/test/spell_effect_test.exs
apps/bezgelor_core/test/spell4_effect_catalog_test.exs
apps/bezgelor_protocol/test/packets/combat_packets_test.exs
apps/bezgelor_world/test/spell4_combat_regression_test.exs
apps/bezgelor_world/test/spell_cast_lifecycle_test.exs
apps/bezgelor_world/test/spell_buff_integration_test.exs
apps/bezgelor_world/test/handler/spell_handler_stats_test.exs
apps/bezgelor_world/test/handler/spell_handler_integration_test.exs
apps/bezgelor_world/test/handler/spell_handler_buff_test.exs
apps/bezgelor_world/test/integration/spell_damage_test.exs
apps/bezgelor_world/test/gameplay_repair_test.exs
```

Les treize nouvelles régressions couvrent le refus de Quick Draw et de ses impacts, l'absence de cooldown et de mutation PV/XP, le refus à l'entrée de résolution, une attaque de démonstration jusqu'aux PV, les GUID invalides, les instances différentes, la portée, l'annulation, le timer répété, la mort, l'XP persistée une seule fois et la cible devenue morte ou hors de portée pendant l'incantation.

La prévention des proxies répétés repose ici sur le refus de toute exécution non vérifiée. Aucun ordonnanceur de phases ni dédoublonnage exécutable des impacts de Quick Draw n'est livré. Les tests de dégâts positifs utilisent les sorts de démonstration existants 1 et 3, jamais une formule supposée de Quick Draw.

Les contrôles ajoutés aux attaques de démonstration portent sur la présence, la vie et la portée. Ils ne constituent pas une validation des factions, immunités, lignes de vue ou contraintes de télégraphe WildStar. Aucune validation en jeu avec le client n'a été effectuée.

**Travail restant et reprise**

`source-nu9` suit la formule, la sélection des phases et les cibles télégraphiques de Quick Draw ; `source-4` reste bloquée par cette preuve manquante. Pour débloquer, fournir un évaluateur documenté des paramètres 12/10 et des règles de dégâts, une interprétation des phases et des contraintes de télégraphe, puis comparer les impacts à des captures ou résultats de référence. Les armures, critiques, boucliers, coefficients et conditions de ciblage ne doivent pas être raccordés au hasard aux mécanismes de démonstration.

Aucun déploiement, redémarrage, changement de personnage de production ou mutation des installations NexusForever/ArcheAge n'a été effectué. Toutes les commandes Docker d'exécution visent le conteneur de test ; seules ses informations et celles de sa base ont été inspectées.
