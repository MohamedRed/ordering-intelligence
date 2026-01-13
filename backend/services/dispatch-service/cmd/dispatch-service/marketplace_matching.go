package main

import (
	"math"
	"sort"
	"time"
)

type marketplaceCandidate struct {
	Deliverer marketplaceDeliverer
	DistanceM float64
	ScoreM    float64
}

func findMarketplaceCandidates(
	deliverers []marketplaceDeliverer,
	storeLat float64,
	storeLng float64,
	initialRadius int,
	expandRadius int,
	maxRadius int,
	limit int,
) []marketplaceCandidate {
	if initialRadius <= 0 {
		initialRadius = marketplaceDefaultInitialRadiusMeters
	}
	if expandRadius <= 0 {
		expandRadius = marketplaceDefaultExpandRadiusMeters
	}
	if maxRadius <= 0 {
		maxRadius = marketplaceDefaultMaxRadiusMeters
	}
	if limit <= 0 {
		limit = marketplaceDefaultCandidateLimit
	}

	radius := initialRadius
	var filtered []marketplaceCandidate
	for radius <= maxRadius {
		filtered = filtered[:0]
		for _, d := range deliverers {
			if d.Lat == 0 || d.Lng == 0 {
				continue
			}
			dist := haversineMeters(storeLat, storeLng, d.Lat, d.Lng)
			if dist <= float64(radius) {
				filtered = append(filtered, marketplaceCandidate{
					Deliverer: d,
					DistanceM: dist,
				})
			}
		}
		if len(filtered) > 0 || radius >= maxRadius {
			break
		}
		radius += expandRadius
	}

	now := time.Now().UTC()
	for i := range filtered {
		filtered[i].ScoreM = scoreMarketplaceDistance(filtered[i].Deliverer, filtered[i].DistanceM, now)
	}

	sortMarketplaceCandidates(filtered)
	if len(filtered) > limit {
		filtered = filtered[:limit]
	}
	return filtered
}

func scoreMarketplaceDistance(deliverer marketplaceDeliverer, distanceMeters float64, now time.Time) float64 {
	if distanceMeters <= 0 {
		return 0
	}
	fairnessBoost := 0.0
	if !deliverer.LastDeliveryAt.IsZero() {
		hours := now.Sub(deliverer.LastDeliveryAt).Hours()
		if hours < 0 {
			hours = 0
		}
		if hours > 4 {
			hours = 4
		}
		fairnessBoost = hours * marketplaceDefaultFairnessBoostMetersPerHr
	}
	score := distanceMeters - fairnessBoost
	if score < 0 {
		return 0
	}
	return score
}

func sortMarketplaceCandidates(candidates []marketplaceCandidate) {
	if len(candidates) < 2 {
		return
	}
	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].ScoreM < candidates[j].ScoreM
	})
}

func haversineMeters(lat1, lng1, lat2, lng2 float64) float64 {
	const earthRadius = 6371000.0
	toRad := func(deg float64) float64 { return deg * math.Pi / 180 }
	lat1R := toRad(lat1)
	lat2R := toRad(lat2)
	dlat := toRad(lat2 - lat1)
	dlng := toRad(lng2 - lng1)

	a := math.Sin(dlat/2)*math.Sin(dlat/2) +
		math.Cos(lat1R)*math.Cos(lat2R)*math.Sin(dlng/2)*math.Sin(dlng/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	return earthRadius * c
}
