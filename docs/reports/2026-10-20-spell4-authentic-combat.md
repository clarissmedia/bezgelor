Investigation du combat Spell4 — 20 octobre 2026

Le travail débloque la lecture fiable des données et le calcul de base documenté par NexusForever, **pas encore un combat de classe fidèle et jouable**. Aucun des onze sorts racines étudiés n'est réactivé. Les PV et récompenses ne reçoivent aucun résultat du nouveau calculateur de diagnostic.

État réellement constaté au démarrage : branche locale `repair/spell4-effects-audit`, commit `a1f2257`, suivi `gameplay/repair/spell4-effects-audit`, aucun changement Git préexistant. Le préfixe `gameplay/` fourni dans la mission désigne le suivi distant, pas le nom de la branche locale. La destination connue reste le dépôt `gameplay` (`clarissmedia/bezgelor`), sans déploiement.

Deux découvertes corrigent le rapport précédent :

- La copie NexusForever installée contient bien le substitut `1337`, mais la branche amont `game_rework`, récupérée au commit **`f9bb26efddbf304003fc8ebf484ac75bc6be84da`** daté du 27 septembre 2026, possède maintenant `DamageCalculator`. Les sources récupérées sont conservées sous `logs/spell4-engine/upstream`, jamais dans l'installation NexusForever. [Source amont figée](https://github.com/NexusForever/NexusForever/blob/f9bb26efddbf304003fc8ebf484ac75bc6be84da/Source/NexusForever.Game/Combat/DamageCalculator.cs).
- Les JSON historiques Spell4 ont des colonnes décalées. `tools/tbl_extractor/tbl_extractor.py::_read_record` ne consomme pas les quatre octets supplémentaires après certains champs texte. `GameTable<T>.ReadEntries` de NexusForever les consomme lorsque le premier offset texte vaut zéro et que le champ suivant n'est pas du texte. Le nouvel extracteur suit cette règle, conserve la précision float32 et rejette les types inconnus. L'en-tête physique fait 96 octets ; le commentaire historique du lecteur Python annonçant 104 n'est pas une spécification fiable. [Lecteur de référence](https://github.com/NexusForever/NexusForever/blob/f9bb26efddbf304003fc8ebf484ac75bc6be84da/Source/NexusForever.GameTable/GameTable.cs).

Les anciennes conclusions « Quick Draw instantané, durée 1000 » sont donc remplacées par les champs relus : **castTime 1000, spellDuration 0, channelMaxTime 1000**. Telekinetic Strike 32893 a castTime 1250 ; Gate 34355 a spellCoolDown 30000. Les anciennes références restent intactes comme traces historiques ; elles ne sont pas les données corrigées.

Les livrables associés sont :

- [Catalogue extrait](../../apps/bezgelor_data/priv/data/spell4_combat_reference.json) : 48 Spell4, 81 effets, 18 tables documentées, schémas, nombres d'enregistrements et SHA-256 des fichiers originaux. Il contient aussi les seuils, prérequis et contraintes utiles.
- [Matrice et vecteurs structurés](2026-10-20-spell4-coverage.json), générés sans démarrer les applications : onze racines, dix types d'effets rencontrés, dix-neuf vecteurs de dégâts de base, aucune autorisation d'exécution.
- [Formules et limites](2026-10-20-spell4-formulas.md).
- [Provenance des sources amont](2026-10-20-spell4-sources.json), avec liens figés et empreintes.
- [Intégrité des entrées](2026-10-20-spell4-input-integrity.json) : les 18 tables originales correspondent aux copies lues et aux empreintes du catalogue ; la réextraction reproduit exactement son SHA-256.
- [Commandes et résultats de validation](2026-10-20-spell4-validation.txt).

**Matrice de couverture**

Les effets mentionnés comprennent les références proxy et les alternatives de seuil, pas une liste d'effets à exécuter ensemble. « Base documentée » signifie calcul arithmétique de référence avec propriétés explicites ; aucun montant final du jeu n'est déclaré validé.

| Classe / compétence | Spell4 | Effets identifiés dans la fermeture des références | Formule / comportement livré | Blocage avant utilisation réelle |
| --- | ---: | --- | --- | --- |
| Warrior — Relentless Strikes | 32078 | 26 Proxy → 70033 ; alternatives 32079/32080 ; 8 Damage, 1 VitalModifier, 17 Fluff | Chargement corrigé, graphe ; base des effets 177056/177098/177121 calculable | Choix des combos, ressource, règles des effets vitaux, cibles et dégâts finaux |
| Warrior — Rampage | 58524 | 26 → 70135 ; seuils 66987/71125/71126 et impacts supplémentaires | Bases 177438/183076/183077/183078 documentées | Séquencement, cumul, conditions et dégâts finaux |
| Spellslinger — Gate | 34355 | 3 ForcedMove, 11 UnitPropertyModifier, 26 Proxy, 4 CCStateSet, 17 Fluff | Données et cooldown corrigés ; déplacement spéculatif serveur rendu inaccessible | ForcedMove, collision/destination, modification de propriété et contrôle des cibles non implémentés |
| Spellslinger — Charged Shot | 34718 | Racine 17 Fluff ; seuils 34720/34722/36691 → 8 Damage ; 73 ModifySpellCooldown | Seuils et trois effets de dégâts retrouvés ; bases calculables séparément | Charge/release, choix du seuil, modification de cooldown, cibles, dégâts finaux |
| Spellslinger — Quick Draw | 43468 | 26 → 43498/43499/43500 ; 8 Damage, 17 Fluff, 80 SpellForceRemove | Cast/channel corrigés ; deux effets de base calculables et références répétées conservées | Phases, tirs réellement déclenchés, sélection/intersection du télégraphe, stats et dégâts finaux |
| Esper — Telekinetic Strike | 32893 | 8 Damage 62159 ; 26 → 30900 ; 1 VitalModifier, 17 Fluff | Cast 1250 corrigé, base calculable | Effets vitaux, cibles, dégâts finaux |
| Esper — Soothe | 33140 | Racine Fluff ; seuils 36897/36941/36942 ; 10 Heal, 1 VitalModifier, 26 | Chargement et alternatives de soin exposés ; aucun soin exécuté | Choix de charge, formule finale de soins, focus et cibles alliées |
| Stalker — Shred | 38765 | 26 → 38767 ; seuil 38766 et impact 39467 ; 8 Damage | Deux effets de base distincts conservés | Choix du second coup, coût de ressource, conditions/cibles et dégâts finaux |
| Engineer — Pulse Blast | 42276 | 26 → 37302 ; trois effets 8 sur les masques de phase 2/4/8 ; 17 Fluff | Cast 1250 corrigé ; chaque base calculable indépendamment | Ne pas additionner automatiquement les trois effets ; phases, ressource, cibles, dégâts finaux |
| Medic — Discharge | 58832 | 8 Damage 141368, 26, 1 VitalModifier, 17, 80 | Canal brut 1250 et base Tech exposés | Ticks/canal, ressources, conditions, cibles et dégâts finaux |
| Medic — Emission | 58841 | 10 Heal 141384, 26, 1, 17, 73, 80 ; TargetFlags 5 | Données de soin/canal conservées ; aucun soin exécuté | Caster + Telegraph ne doit pas devenir une seule cible ; canal, focus, soin et cooldown |

Les associations de classe proviennent des lignes Spell4Base reliées correctement : Warrior 1, Engineer 2, Esper 3, Medic 4, Stalker 5, Spellslinger 7. Les noms ont servi à choisir des objets d'étude, jamais à déduire leur comportement.

**Quick Draw, directement depuis les tables originales**

- Spell4 43468 pointe vers Spell4Base 27638, tierIndex 1. Cast/channel 1000 ms ; channelInitialDelay 366, channelPulseTime 634. Ces trois durées ne définissent pas à elles seules le nombre de tirs.
- Les neuf effets racines sont 196513–196519, 196521, 196522. Six références concernent les deux impacts : trois vers 43498 et trois vers 43499, sur les masques 2/4/8. Les deux autres proxies concernent 43500, qui porte l'effet Fluff 99472. L'effet 196521 est SpellForceRemove, pas un troisième type de proxy de dégâts. Six occurrences de références ne prouvent pas six tirs.
- SpellPhase contient cinq lignes 5882–5886, `(orderIndex, phaseDelay, phaseFlags)` : `(0,0,0)`, `(1,366,512)`, `(2,200,0)`, `(3,200,4)`, `(4,234,0)`. Ni la vieille copie ni `Spell.ExecuteEffects` amont ne fournissent un ordonnanceur fiable de ces masques. Aucun ordre d'application n'a été extrapolé.
- Spell4Telegraph 39868 relie la racine au télégraphe 3693 ; 6839 et 6837 relient les impacts à 3694. Shape 8 est LongCone. Paramètres bruts `3,27,15,0,20,0`, décalage Z `-2`. Les flags de dégâts diffèrent entre 3693 et 3694.
- Les impacts référencent Spell4AoeTargetConstraints **405** : targetCount **3**, minRange 0, maxRange **25**, angle 360, targetSelection 1. Cette limite est distincte de la forme du cône et ne définit pas l'ordre de sélection de trois cibles. Les collisions, lignes de vue, rayons de collision, orientation et politiques de sélection ne sont pas validés. Les routines de cône amont ne suffisent pas à lever ces inconnues.
- Les effets 99526 et 99528 ont type 8, damageType 1 Physical, targetFlags 4 Telegraph. Leurs paramètres sont 12 AssaultPower et 10 PerLevel, avec les coefficients float32 originaux ; GameFormula 1266 fournit les facteurs 0.25.
- Les champs directs de coût sont nuls. Ce constat ne prouve pas l'absence de toute interaction de ressource. Le runner 3 est une référence d'affichage et son prérequis 20117 contient notamment UnderSpell 15 / valeur 47439. Le type vital SpellSurge 0x13 existe dans le code ; aucune consommation ou génération n'en a été déduite.
- Cooldown direct 0 ; référence globale 82 → 1000 ms. Les impacts portent notamment globalCooldownEnum 3 et référence 145 → 500 ms. Le contrat exact de ces champs ne peut pas être remplacé par un GCD uniforme appliqué à chaque proxy.

**Changements dans le code**

`BezgelorData.Tbl` lit les tables sans les modifier. `tools/extract_spell4_combat.exs` sélectionne mécaniquement les onze racines et suit seulement les champs de référence explicites : Proxy 26/DataBits00, Spell4Thresholds et cast events. Il n'interprète ni les conditions ni les phases. Son seul fichier de sortie doit être un JSON situé dans le workspace.

`BezgelorData.Spell4Catalog` fournit les lignes brutes et leur provenance. Le facade `BezgelorData.get_spell4_entry/1` utilise les 48 lignes corrigées, puis garde le comportement historique hors de ce sous-ensemble. Les autres JSON ne sont pas régénérés. `source-7` suit cet audit restant.

`Spell4Effect` nomme seulement les dix codes réellement rencontrés. `Spell4Chain` matérialise une seule fois chaque nœud de sort, conserve toutes les arêtes et signale cycles, références absentes et limites de profondeur/taille. Son résultat annonce toujours `execution_enabled: false` ; il n'est jamais converti en liste de dégâts à appliquer.

`Spell4Context` exige les opérandes bruts. `Spell4BaseDamage` reproduit uniquement l'arithmétique de base documentée, avec erreurs explicites pour opérandes manquants, paramètres non pris en charge, NPC, soins, valeurs non finies ou dépassements. Aucun raccourci ne remplace AssaultRating par le `power` du système de démonstration.

L'ancienne API `Spell.effect_analysis/1` est conservée pour compatibilité avec son petit catalogue de recherche ; `Spell4Diagnostics` et `Spell4Catalog` sont les interfaces de cette nouvelle extraction.

`Spell4Diagnostics.inspect_spell/2` expose graphe, bases éventuelles, phases, seuils, télégraphes, contraintes et blocages. Il n'accède ni à la base de données ni aux processus de monde. `tools/report_spell4_combat.exs` produit la matrice JSON et les vecteurs avec `mix run --no-start`.

`Spell4CombatSupport` refuse les 48 entrées avant timer, cooldown ou effet. Cela ferme aussi le chemin de Gate qui modifiait la position serveur de 30 unités sans ForcedMove fonctionnel. Les formules de démonstration existantes restent fonctionnellement inchangées ; leurs commentaires ne les qualifient plus de formules WildStar vérifiées.

**Validation et portée du résultat**

La compilation complète forcée avec avertissements bloquants utilise `MIX_ENV=test MIX_BUILD_PATH=/tmp/bezgelor-spell4-build`. La campagne ciblée élargie inclut explicitement les tests d'intégration et traite les avertissements des tests comme des erreurs. Les commandes et résultats exacts sont dans le journal associé. Les tests distinguent lecture/calcul purs et circuit d'intégration avec PostgreSQL de test.

Résultat final : **158 tests, 0 échec** — core 57, données 7, protocole 23, monde 71 — dont **28 nouvelles régressions**. La compilation complète stricte réussit. Le formatage des 19 fichiers Elixir modifiés est vérifié séparément. Les campagnes intermédiaires ne sont pas additionnées à ce total.

La validation en jeu n'a pas été effectuée. Les tests positifs de PV, mort et XP persistée utilisent toujours les sorts de démonstration existants. Les nouveaux vecteurs des six classes valident des calculs de base sur propriétés synthétiques explicites, jamais un personnage de production ou un montant final observé.

La compilation et les tests ciblés ne certifient pas la suite globale du dépôt : `mix precommit` échoue au contrôle de formatage sur 43 fichiers préexistants, suivis par `source-3`. Son étape de tests globaux n'est pas atteinte. Aucun formatage global n'est effectué.

La tâche `source-6` couvre le catalogue corrigé, les calculs documentés, l'inspection et cette campagne. `source-nu9` et `source-4` restent ouverts/bloqués pour la résolution complète ; `source-7` couvre les autres extractions historiques. La reprise doit d'abord établir les phases/événements, les propriétés autoritatives et les politiques de cible, puis confronter les résultats finaux à une référence indépendante. Une formule amont partiellement implémentée n'est pas une preuve de fidélité intégrale au serveur original.

Aucun service de production, aucune installation NexusForever/ArcheAge et aucun compte ou personnage de production n'a été modifié. Les tables originales sont restées en lecture seule ; les extractions s'exécutent sur leurs copies dans le workspace. Aucun déploiement n'est effectué.
