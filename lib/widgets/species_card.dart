import 'package:flutter/material.dart';
import '../models/tree_species.dart';

class SpeciesCard extends StatelessWidget {
  final TreeSpecies species;

  const SpeciesCard({
    Key? key,
    required this.species,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              species.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '適合地區: ${species.suitableRegions.join(", ")}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              '碳吸收效率: ${species.calculateCarbonAbsorption(20).toStringAsFixed(2)} kg CO₂/年',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
