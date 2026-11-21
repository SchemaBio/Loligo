package service

import (
	"errors"

	"github.com/SchemaBio/Loligo/internal/model"
)

// Retained for compatibility with callers matching the historical error.
var ErrFamilyAnalysisUnavailable = errors.New("family analysis is not available yet")

func requireAnalysisAvailable(template string) error {
	for _, item := range model.PlannedOncologyPipelines() {
		if item.Template == template {
			return errors.New(item.ResourceError)
		}
	}
	return nil
}
